# Codex Gateway Ubuntu 部署指南

这份文档面向从零开始的 Ubuntu 服务器部署。
目标是把 `server-runtime-bundle` 部署成一个稳定、可维护、尽量不踩坑的网关服务。

## 适用场景

- Ubuntu 22.04 LTS 或 24.04 LTS
- 通过 `Bun + systemd` 运行服务
- 推荐放在 `Nginx` 或 `Caddy` 后面
- 不建议直接把 `:4777` 裸露到公网

## 部署原则

1. 服务进程尽量不要用 `root` 运行。
2. 网关本身只监听本机或内网，公网入口交给 `Nginx` 或 `Caddy` 做 HTTPS。
3. 必须配置 `OAUTH_APP_ADMIN_TOKEN` 和 `OAUTH_APP_ENCRYPTION_KEY`。
4. 默认不要开启内置 forward proxy，除非你明确需要它。
5. 持久化时保留整个 `data/` 目录，不只是 `accounts.db`。

## 1. 安装系统依赖

先更新包索引：

```bash
sudo apt update
sudo apt install -y curl unzip ca-certificates ufw
```

如果你准备使用 Nginx：

```bash
sudo apt install -y nginx
```

如果你准备使用 Caddy：

```bash
sudo apt install -y caddy
```

通常二选一即可，不需要同时安装。

## 2. 安装 Bun

用官方安装脚本安装 Bun：

```bash
curl -fsSL https://bun.sh/install | bash
```

让当前 shell 立即生效：

```bash
source ~/.bashrc
```

确认版本：

```bash
bun --version
```

如果你是通过 `root` 安装，后面给专用用户运行服务时，也要确保那个用户自己的 PATH 里能找到 `bun`。

## 3. 创建专用用户和部署目录

创建一个不带登录 shell 的系统用户：

```bash
sudo useradd --system --create-home --home-dir /opt/codex-gateway --shell /usr/sbin/nologin codex-gateway
```

创建部署目录：

```bash
sudo mkdir -p /opt/codex-gateway
sudo chown -R codex-gateway:codex-gateway /opt/codex-gateway
```

推荐最终目录结构像这样：

```text
/opt/codex-gateway/server-runtime-bundle
```

## 4. 上传 bundle

把当前仓库里的 `server-runtime-bundle` 整个目录上传到 Ubuntu 服务器，例如：

```bash
scp -r server-runtime-bundle your-user@your-server:/tmp/
```

登录服务器后移动到正式目录：

```bash
sudo mv /tmp/server-runtime-bundle /opt/codex-gateway/
sudo chown -R codex-gateway:codex-gateway /opt/codex-gateway/server-runtime-bundle
```

## 5. 配置 `.env`

切换到部署目录：

```bash
cd /opt/codex-gateway/server-runtime-bundle
```

复制环境模板：

```bash
cp .env.example .env
```

建议最少修改这些值：

```env
OAUTH_APP_HOST=127.0.0.1
OAUTH_APP_PORT=4777
OAUTH_APP_DATA_DIR=/opt/codex-gateway/server-runtime-bundle/data
OAUTH_APP_WEB_DIR=/opt/codex-gateway/server-runtime-bundle/src/web

OAUTH_APP_ADMIN_TOKEN=换成你自己的高强度随机字符串
OAUTH_APP_ENCRYPTION_KEY=换成64位hex随机字符串

OAUTH_APP_FORWARD_PROXY_ENABLED=0
OAUTH_APP_FORWARD_PROXY_ENFORCE_ALLOWLIST=1
```

这里有两个关键建议：

- 如果你会放在 Nginx 或 Caddy 后面，`OAUTH_APP_HOST` 推荐写 `127.0.0.1`，不要直接写 `0.0.0.0`。
- `OAUTH_APP_ENCRYPTION_KEY` 一旦开始正式使用后不要轻易更换，否则旧密文可能无法正确解密。

生成随机密钥的例子：

```bash
openssl rand -hex 32
```

管理令牌也建议用随机值，例如：

```bash
openssl rand -hex 24
```

## 6. 安装依赖并首次启动

安装依赖：

```bash
bun install --production
```

首次前台启动，确认没有配置错误：

```bash
./start.sh
```

如果看到类似服务启动日志，再开一个终端执行健康检查：

```bash
curl http://127.0.0.1:4777/api/health
```

如果返回里有 `ok: true`，说明服务已正常跑起来。

确认无误后，按 `Ctrl+C` 停掉前台进程，再继续配 `systemd`。

## 7. 配置 systemd

当前 bundle 自带了一个基础示例：

```text
systemd/codex-gateway.service
```

如果你先用这个示例，至少要确认以下路径和权限是对的：

- `WorkingDirectory`
- `ExecStart`

安装服务文件：

```bash
sudo cp systemd/codex-gateway.service /etc/systemd/system/codex-gateway.service
sudo systemctl daemon-reload
sudo systemctl enable codex-gateway
sudo systemctl start codex-gateway
```

查看状态：

```bash
sudo systemctl status codex-gateway
sudo journalctl -u codex-gateway -f
```

如果你要更稳妥的公网部署，推荐把 systemd 服务进一步加固，至少补上这些项：

- `User=codex-gateway`
- `Group=codex-gateway`
- `EnvironmentFile=/opt/codex-gateway/server-runtime-bundle/.env`
- `NoNewPrivileges=true`
- `PrivateTmp=true`
- `ProtectSystem=strict`
- `ProtectHome=true`
- `ReadWritePaths=/opt/codex-gateway/server-runtime-bundle/data`

## 8. 配置 UFW

先打开基本策略：

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
```

开放 SSH：

```bash
sudo ufw allow OpenSSH
```

如果你使用 Nginx：

```bash
sudo ufw allow 'Nginx Full'
```

如果你使用 Caddy：

```bash
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
```

不建议直接开放 `4777` 到公网。

如果你只是内网调试，最多只对可信网段放行，例如：

```bash
sudo ufw allow from 192.168.0.0/16 to any port 4777 proto tcp
```

启用 UFW：

```bash
sudo ufw enable
sudo ufw status verbose
```

## 9. 防止公网裸露

这一步很重要。

当前项目本身可以直接监听 HTTP 端口，但不建议把 `http://your-server:4777` 直接开放到公网，原因包括：

- 管理页和管理接口本质上是高权限入口
- 没有内建 HTTPS
- 管理令牌会参与浏览器和 API 调用
- 如果用户绕过启动脚本直接运行服务，错误配置的风险会放大

更安全的做法是：

1. 网关只监听 `127.0.0.1:4777`
2. 公网只开放 `80/443`
3. 用 `Nginx` 或 `Caddy` 反向代理到本地网关
4. 管理访问只走 HTTPS
5. 把 `.env` 和 `data/` 目录权限收紧到专用用户

建议权限：

```bash
chmod 600 /opt/codex-gateway/server-runtime-bundle/.env
chmod 700 /opt/codex-gateway/server-runtime-bundle/data
sudo chown codex-gateway:codex-gateway /opt/codex-gateway/server-runtime-bundle/.env
sudo chown -R codex-gateway:codex-gateway /opt/codex-gateway/server-runtime-bundle/data
```

## 10. 推荐放在 Nginx 或 Caddy 后面

### 方案 A：Nginx

适合你想自己控制证书、访问策略和反向代理细节的情况。

基础思路：

- `listen 443 ssl http2`
- 反向代理到 `http://127.0.0.1:4777`
- 正确传递 `Host`、`X-Forwarded-*`
- 保证长连接、SSE 不被错误缓存或缓冲

如果你要做 Let’s Encrypt，可以配 `certbot`：

```bash
sudo apt install -y certbot python3-certbot-nginx
```

### 方案 B：Caddy

适合你想尽量少配东西、自动拿 HTTPS 证书的情况。

基础思路：

- 用域名直接反代到 `127.0.0.1:4777`
- 让 Caddy 自动申请和续期证书
- 外网只开放 `80/443`

## 11. 登录方式建议

Ubuntu 远程部署后，新增 OAuth 账号时不要默认使用浏览器自动回调模式。

推荐优先级：

1. `headless`
2. `manual-code`
3. `browser` 只在你通过远程桌面登录到服务器本机时使用

原因是浏览器自动回调固定写死到：

```text
http://localhost:1455/auth/callback
```

如果你是在自己电脑浏览器里打开服务器页面，这里的 `localhost` 指向的是你的电脑，不是 Ubuntu 服务器。

## 12. 运维建议

- 备份整个 `data/` 目录
- 保留 `accounts.db`、`accounts.db-wal`、`accounts.db-shm`
- 保留 `settings.json` 和 `bootstrap.log`
- 不要把 `OAUTH_APP_ENCRYPTION_KEY` 只保存在服务器本地
- 升级前先备份 `data/` 和 `.env`

## 13. 最简上线路径

如果你要一条最稳妥的 Ubuntu 路线，可以直接按下面走：

1. 安装 Bun
2. 创建 `codex-gateway` 专用用户
3. 上传 `server-runtime-bundle` 到 `/opt/codex-gateway`
4. 把 `OAUTH_APP_HOST` 配成 `127.0.0.1`
5. 配好 `OAUTH_APP_ADMIN_TOKEN` 和 `OAUTH_APP_ENCRYPTION_KEY`
6. 执行 `bun install --production`
7. 先用 `./start.sh` 验证
8. 再挂到 `systemd`
9. 外面放 Nginx 或 Caddy
10. UFW 只放 `SSH` 和 `80/443`

## 14. 什么时候算部署成功

满足下面这些，就可以认为 Ubuntu 部署已经成型：

- `systemctl status codex-gateway` 正常
- `curl http://127.0.0.1:4777/api/health` 返回 `ok: true`
- 浏览器通过 HTTPS 域名能打开管理页
- 客户端能通过你的反向代理地址访问 `/v1/models` 或 `/v1/responses`
- 你能在服务端看到数据文件正确写入 `data/`
