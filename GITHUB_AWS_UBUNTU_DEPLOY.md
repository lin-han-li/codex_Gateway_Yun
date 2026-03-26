# GitHub -> AWS Ubuntu 部署实操

这份文档按你现在这次场景来写：

- 本地目录：`server-runtime-bundle`
- GitHub 仓库：`https://github.com/lin-han-li/codex_Gateway_Yun.git`
- 服务器系统：Ubuntu
- 推荐部署目录：`/opt/codex-gateway/server-runtime-bundle`
- 推荐公网入口：`Caddy + 80/443 + 域名`

如果你只是想先跑通，直接按下面命令执行即可。

## 1. 本地先推到 GitHub

先在本地打开 PowerShell，进入项目目录：

```powershell
cd C:\Users\pengjianzhong\Desktop\server-runtime-bundle
```

如果当前仓库还没有远端，执行：

```powershell
git remote add origin https://github.com/lin-han-li/codex_Gateway_Yun.git
```

如果你之前已经配过 `origin`，改成：

```powershell
git remote set-url origin https://github.com/lin-han-li/codex_Gateway_Yun.git
```

确认远端：

```powershell
git remote -v
```

首次提交并推送：

```powershell
git add .
git commit -m "chore: initial server runtime bundle"
git branch -M main
git push -u origin main
```

如果 GitHub 仓库不是空仓库，而是已经有 README 或别的初始化文件，先执行：

```powershell
git pull --rebase origin main
git push -u origin main
```

## 2. AWS 侧先做这几件事

在 EC2 安全组里建议这样放行：

- `22/tcp`：只允许你的管理 IP
- `80/tcp`：允许公网
- `443/tcp`：允许公网

不要直接把 `4777/tcp` 和 `4778/tcp` 暴露到公网。

如果你准备走 HTTPS，先把域名 A 记录指向 EC2 公网 IP。

## 3. 登录 Ubuntu 并安装基础环境

先登录服务器：

```bash
ssh ubuntu@<EC2_PUBLIC_IP>
```

安装基础依赖和 Caddy：

```bash
sudo apt update
sudo apt install -y git curl unzip ca-certificates ufw caddy
```

安装 Bun：

```bash
curl -fsSL https://bun.sh/install | bash
```

让当前 shell 立即生效：

```bash
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"
```

建议顺手写进 `~/.bashrc`：

```bash
echo 'export BUN_INSTALL="$HOME/.bun"' >> ~/.bashrc
echo 'export PATH="$BUN_INSTALL/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

确认安装成功：

```bash
git --version
bun --version
```

把 `bun` 放到 systemd 一定能找到的位置：

```bash
sudo install -m 0755 "$HOME/.bun/bin/bun" /usr/local/bin/bun
```

再次确认：

```bash
/usr/local/bin/bun --version
```

## 4. 从 GitHub 克隆项目

创建部署目录并克隆：

```bash
sudo mkdir -p /opt/codex-gateway
sudo chown ubuntu:ubuntu /opt/codex-gateway
cd /opt/codex-gateway
git clone https://github.com/lin-han-li/codex_Gateway_Yun.git server-runtime-bundle
cd /opt/codex-gateway/server-runtime-bundle
```

运行仓库自带的初始化脚本：

```bash
chmod +x scripts/ubuntu-post-clone-setup.sh
./scripts/ubuntu-post-clone-setup.sh
```

这一步会做几件事：

- 创建 `codex-gateway` 系统用户
- 把目录权限切给 `codex-gateway`
- 如果 `.env` 不存在，就从 `.env.example` 复制
- 执行 `bun install --production`

## 5. 配置 `.env`

编辑环境变量：

```bash
nano /opt/codex-gateway/server-runtime-bundle/.env
```

至少改这些值：

```env
OAUTH_APP_HOST=127.0.0.1
OAUTH_APP_PORT=4777
OAUTH_APP_DATA_DIR=/opt/codex-gateway/server-runtime-bundle/data
OAUTH_APP_WEB_DIR=/opt/codex-gateway/server-runtime-bundle/src/web

OAUTH_APP_ADMIN_TOKEN=replace-with-a-random-admin-token
OAUTH_APP_ENCRYPTION_KEY=replace-with-64-hex-chars

OAUTH_APP_FORWARD_PROXY_ENABLED=0
OAUTH_APP_FORWARD_PROXY_ENFORCE_ALLOWLIST=1
```

生成 64 位十六进制加密密钥：

```bash
openssl rand -hex 32
```

生成管理员令牌：

```bash
openssl rand -hex 24
```

建议把 `.env` 权限收紧：

```bash
sudo chown codex-gateway:codex-gateway /opt/codex-gateway/server-runtime-bundle/.env
sudo chmod 600 /opt/codex-gateway/server-runtime-bundle/.env
sudo chmod 700 /opt/codex-gateway/server-runtime-bundle/data
```

## 6. 先前台验证一次

先做预检：

```bash
cd /opt/codex-gateway/server-runtime-bundle
sudo -u codex-gateway env PATH="/usr/local/bin:/usr/bin:/bin:$PATH" ./scripts/check-ubuntu-prereqs.sh
```

前台启动：

```bash
sudo -u codex-gateway env PATH="/usr/local/bin:/usr/bin:/bin:$PATH" ./start.sh
```

新开一个终端检查健康状态：

```bash
curl http://127.0.0.1:4777/api/health
```

如果返回里有 `ok`，说明服务已经跑起来了。确认无误后按 `Ctrl+C` 停掉前台进程。

## 7. 配置 systemd

安装服务文件：

```bash
sudo cp /opt/codex-gateway/server-runtime-bundle/systemd/codex-gateway.service /etc/systemd/system/codex-gateway.service
sudo systemctl daemon-reload
sudo systemctl enable codex-gateway
sudo systemctl start codex-gateway
```

查看状态：

```bash
sudo systemctl status codex-gateway
sudo journalctl -u codex-gateway -f
```

如果你修改了 `.env`，重启服务：

```bash
sudo systemctl restart codex-gateway
```

## 8. 配置 Caddy 反向代理

把仓库里的示例配置复制到 Caddy：

```bash
sudo cp /opt/codex-gateway/server-runtime-bundle/caddy/Caddyfile /etc/caddy/Caddyfile
```

编辑域名：

```bash
sudo nano /etc/caddy/Caddyfile
```

把里面的 `gateway.example.com` 改成你的真实域名。

检查配置：

```bash
sudo caddy validate --config /etc/caddy/Caddyfile
```

重启 Caddy：

```bash
sudo systemctl restart caddy
sudo systemctl status caddy
```

## 9. 开启防火墙

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow OpenSSH
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable
sudo ufw status verbose
```

## 10. 最终验证

本机健康检查：

```bash
curl http://127.0.0.1:4777/api/health
```

公网 HTTPS 检查：

```bash
curl -I https://<YOUR_DOMAIN>/api/health
```

## 11. 后续更新命令

以后你本地改完代码并推到 GitHub 后，服务器更新只需要：

```bash
cd /opt/codex-gateway/server-runtime-bundle
sudo -u codex-gateway git pull --ff-only origin main
sudo -u codex-gateway env PATH="/usr/local/bin:/usr/bin:/bin:$PATH" bun install --production
sudo systemctl restart codex-gateway
sudo systemctl restart caddy
```

## 12. 两个常见坑

### 坑 1：GitHub 仓库是私有仓库

如果服务器上 `git clone` 提示没有权限，就改用下面任一方式：

- 给服务器配置 GitHub SSH key，再用 SSH 地址克隆
- 用 PAT 临时克隆私有仓库

SSH 方式示例：

```bash
git clone git@github.com:lin-han-li/codex_Gateway_Yun.git server-runtime-bundle
```

### 坑 2：没有域名

没有域名时，不建议直接把 `4777` 暴露公网长期使用。

临时测试可以只做：

```bash
curl http://127.0.0.1:4777/api/health
```

或者在 AWS 安全组里把 `4777` 只开放给你的固定 IP 做短期测试，确认没问题后再收回。
