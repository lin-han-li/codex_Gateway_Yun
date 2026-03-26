# Codex Gateway 服务器部署包

这个文件夹是从原项目中整理出来的最小服务端运行包，只保留服务器部署所需的源码、依赖声明、启动脚本和运维说明。

## 包内文件

- `src/`: Bun 服务源码和 Web 管理页
- `package.json`: 精简后的运行时依赖
- `bun.lock`: 依赖锁文件
- `tsconfig.json`: 类型检查配置
- `.env.example`: 环境变量样例
- `start.sh`: Linux/macOS 启动脚本
- `start.ps1`: Windows 启动脚本
- `scripts/generate-secrets.ts`: 生成随机管理令牌和加密密钥
- `scripts/check-ubuntu-prereqs.sh`: Ubuntu 启动前预检脚本
- `systemd/codex-gateway.service`: Linux `systemd` 加固示例
- `systemd/codex-gateway.env.example`: `systemd` 环境文件模板
- `UBUNTU_DEPLOY.md`: Ubuntu 部署手册
- `CLIENT_API_GUIDE.md`: 客户端/API 接入指南
- `WINDOWS_REMOTE_JSON_IMPORT.md`: Windows 远程导入 JSON 账号手册
- `nginx/`: Nginx HTTPS 反向代理示例
- `caddy/`: Caddy 自动 HTTPS 反向代理示例
- `PROJECT_NOTES.md`: 项目梳理结论

## 推荐阅读顺序

- Ubuntu 落地部署：`UBUNTU_DEPLOY.md`
- 客户如何发请求到你的网关：`CLIENT_API_GUIDE.md`
- Windows 管理员如何远程导入本地 JSON 账号文件：`WINDOWS_REMOTE_JSON_IMPORT.md`
- Ubuntu 启动前预检：`scripts/check-ubuntu-prereqs.sh`
- 反向代理：
  - Nginx：`nginx/codex-gateway.conf`
  - Caddy：`caddy/Caddyfile`

## 运行前提

- Bun 1.2.x
- 出站网络可访问：
  - `auth.openai.com`
  - `chatgpt.com`
  - `api.openai.com`
  - `openai.com`
- 如果你要绑定到非回环地址，如 `0.0.0.0`、`192.168.x.x`，必须准备：
  - `OAUTH_APP_ENCRYPTION_KEY`
  - `OAUTH_APP_ADMIN_TOKEN`

## 首次部署

1. 安装 Bun。
2. 把整个 `server-runtime-bundle` 文件夹上传到服务器。
3. 复制环境样例：

```bash
cp .env.example .env
```

4. 修改 `.env` 里的至少这些值：

- `OAUTH_APP_HOST`
- `OAUTH_APP_PORT`
- `OAUTH_APP_ADMIN_TOKEN`
- `OAUTH_APP_ENCRYPTION_KEY`
- `OAUTH_APP_DATA_DIR`

5. 安装依赖：

```bash
bun install --production
```

如需快速生成随机密钥，也可以先执行：

```bash
bun run generate:secrets
```

6. 启动服务：

Linux/macOS:

```bash
chmod +x start.sh
./start.sh
```

Windows PowerShell:

```powershell
.\start.ps1
```

如果你是在 Ubuntu 上正式部署，建议先执行：

```bash
chmod +x scripts/check-ubuntu-prereqs.sh
./scripts/check-ubuntu-prereqs.sh
```

## 推荐的密钥生成方式

Linux/macOS:

```bash
openssl rand -hex 32
```

Windows PowerShell:

```powershell
[Convert]::ToHexString([byte[]](1..32 | ForEach-Object { Get-Random -Maximum 256 }))
```

把输出结果填到 `OAUTH_APP_ENCRYPTION_KEY`。`OAUTH_APP_ADMIN_TOKEN` 建议使用另一段随机字符串。

如果你已经安装了 Bun，也可以直接运行：

```bash
bun run generate:secrets
```

## 登录方式与远程部署限制

当前代码真正启用的 OAuth provider 只有 `ChatGPT`。

支持的 3 种 ChatGPT 登录方式：

- `browser`: 自动浏览器回调，固定回调地址是 `http://localhost:1455/auth/callback`
- `manual-code`: 手动粘贴回调 URL 或 `code`
- `headless`: 设备码登录

远程服务器部署时请注意：

- 如果你是通过浏览器远程访问这台服务器的 Web 管理页，`browser` 模式通常不适合直接使用，因为 OAuth 回调写死到 `localhost:1455`。
- 远程环境优先使用 `headless`。
- 如果必须使用 `browser`，通常需要通过远程桌面在服务器本机完成登录。
- `manual-code` 可以作为折中方案，但用户必须能拿到最终回调 URL 或授权码。
- 内置 forward proxy 在这个部署包的 `.env.example` 里默认是关闭的，只有明确需要时再开启。

## 持久化目录

默认建议把数据放在 `./data`，这个目录需要持久化保存。

至少要保留这些文件：

- `accounts.db`
- `accounts.db-wal`
- `accounts.db-shm`
- `settings.json`
- `bootstrap.log`

不要把仓库原来的 `data/` 直接覆盖到生产服务器，除非你明确要迁移现有账号数据。

## 通过 systemd 托管

1. 修改 `systemd/codex-gateway.service` 里的实际路径。
2. 按 `systemd/codex-gateway.env.example` 生成环境文件。
3. 链接到系统目录：

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

Ubuntu 公网部署更推荐直接看 `UBUNTU_DEPLOY.md`，里面已经包含：

- 专用用户
- UFW
- Nginx/Caddy
- 避免公网裸露 `4777`
- 远程 OAuth 登录限制

## 访问与管理

- 健康检查：`GET /api/health`
- Web 管理页：`GET /`
- 如果设置了 `OAUTH_APP_ADMIN_TOKEN`，所有 `/api/*` 管理接口都要带 `x-admin-token`
- 对外提供给客户端的 OpenAI 兼容入口是 `/v1/*`

快速原则：

- 管理员用 `/api/*`
- 客户业务流量用 `/v1/*`
- 客户端应使用 `Authorization: Bearer <virtual_key>`
- 不要让普通客户使用 `4778`
- 如果前面挂了 Nginx/Caddy，优先给客户发域名 HTTPS 地址，而不是裸 `4777`

## 这个包刻意没有包含什么

- `electron/`: 仅桌面壳使用
- `build/` 和 `dist/`: 桌面打包产物
- `node_modules/`: 服务器上重新安装更干净
- 仓库根目录 `data/`: 避免误带现有账号和令牌
- `scripts/`: 主要是测试和审计脚本，不是运行必需

## 已知差异

- 仓库 README 写了 GitHub Copilot Device Flow，但当前代码里的 `ProviderRegistry` 并没有注册它。
- 仓库 README 里把非回环绑定时的 `admin token` 写成“required”；代码层面真正硬性校验的是 `OAUTH_APP_ENCRYPTION_KEY`。这个部署包仍然把 `admin token` 当成服务器部署必填项处理。
