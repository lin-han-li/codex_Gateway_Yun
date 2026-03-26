# Windows 远程导入 JSON 账号手册

这份手册用于说明：当网关已经部署在 Ubuntu 或其他远程服务器后，管理员如何在自己的 Windows 电脑上，把本地 `.json` 账号文件远程导入到网关。

## 1. 先说结论

- 可以远程导入。
- 不需要先把 `.json` 文件手工上传到 Ubuntu 服务器。
- Windows 浏览器或 PowerShell 会先读取你本地文件的内容，再把 JSON 内容发送到网关管理接口：
  - `POST /api/accounts/import-json`
- 服务端收到的是 JSON 内容，不是你 Windows 上的文件路径。

## 2. 适用前提

开始前请确认这几件事：

- 网关已经部署完成，并且你可以访问管理地址。
- 你知道管理令牌 `OAUTH_APP_ADMIN_TOKEN`。
- 公网场景已经配置 HTTPS。
- 你的 JSON 文件内容合法，并且至少包含 `access_token` 或 `accessToken`。

推荐管理地址形式：

```text
https://gateway.example.com/
```

如果只是内网测试，也可以是：

```text
http://SERVER_IP:4777/
```

但只要 JSON 里包含真实 `access_token`、`refresh_token`、`id_token`，就不要在公网用明文 HTTP。

## 3. 最推荐的方式：浏览器导入

这是最适合手工操作的方式。

### 3.1 操作步骤

1. 在 Windows 电脑上打开你的网关管理页。
2. 如果浏览器里还没有保存管理令牌，直接用下面这种地址打开一次：

```text
https://gateway.example.com/?admin_token=你的管理令牌
```

3. 进入“账号管理”页面。
4. 点击“导入 JSON 账号”。
5. 在 Windows 本地选择一个或多个 `.json` 文件。
6. 浏览器会在本地读取这些文件，然后把解析后的 JSON 内容发送到服务端。
7. 导入成功后，页面会刷新账号列表；如果 JSON 里显式设置了 `issueVirtualKey: true`，还会一起创建虚拟 key。

### 3.2 这一步到底发生了什么

实际流程是：

1. 你的浏览器读取 Windows 本地文件内容。
2. 浏览器本地完成 `JSON.parse(...)`。
3. 浏览器把 JSON 请求体 POST 到：

```text
/api/accounts/import-json
```

4. 服务端校验字段并落库。

所以这里并不是“服务器远程读取你的 Windows 文件”，而是“Windows 本地把文件内容发给服务器”。

## 4. 自动化或批量时：Windows PowerShell 导入

如果你想批量执行、做脚本，或者不想打开网页，可以直接从 Windows PowerShell 调接口。

### 4.1 单文件导入

```powershell
$json = Get-Content -Raw .\accounts.json

Invoke-RestMethod `
  -Uri "https://gateway.example.com/api/accounts/import-json" `
  -Method Post `
  -Headers @{
    "x-admin-token" = "YOUR_ADMIN_TOKEN"
    "Content-Type"  = "application/json"
  } `
  -Body $json
```

### 4.2 用 curl.exe 导入

```powershell
curl.exe "https://gateway.example.com/api/accounts/import-json" `
  -H "x-admin-token: YOUR_ADMIN_TOKEN" `
  -H "Content-Type: application/json" `
  --data-binary "@accounts.json"
```

### 4.3 什么时候更适合 PowerShell

- 要批量处理多个 JSON 文件。
- 要做自动化导入脚本。
- 不想通过浏览器手工点击。
- 需要把导入过程接进自己的运维流程。

## 5. JSON 文件怎么写

### 5.1 最小可用格式

至少要有 `access_token` 或 `accessToken`。

```json
{
  "email": "user@example.com",
  "access_token": "ACCESS_TOKEN"
}
```

### 5.2 更完整的单账号示例

```json
{
  "type": "chatgpt",
  "email": "user@example.com",
  "access_token": "ACCESS_TOKEN",
  "refresh_token": "REFRESH_TOKEN",
  "id_token": "ID_TOKEN",
  "last_refresh": "2026-03-26T10:00:00Z",
  "issueVirtualKey": true,
  "keyName": "Imported Key"
}
```

### 5.3 批量导入示例

```json
[
  {
    "email": "a@example.com",
    "access_token": "ACCESS_TOKEN_A"
  },
  {
    "email": "b@example.com",
    "access_token": "ACCESS_TOKEN_B",
    "issueVirtualKey": true,
    "keyName": "B Key"
  }
]
```

### 5.4 常用字段说明

- `email`: 账号邮箱。建议提供，便于管理。
- `access_token` 或 `accessToken`: 必需字段，二选一即可。
- `refresh_token` 或 `refreshToken`: 可选。
- `id_token` 或 `idToken`: 可选。
- `last_refresh` 或 `lastRefresh`: 可选。
- `issueVirtualKey`: 是否在导入后自动签发虚拟 key。默认是 `false`。
- `keyName`: 自动签发虚拟 key 时使用的名字。

## 6. 服务端会怎么处理

导入接口会按下面的逻辑处理你的 JSON：

- 支持“单个对象”或“对象数组”。
- 单次最多导入 500 条记录。
- 会校验 JSON 结构。
- 会要求 `access_token` 或 `accessToken` 存在。
- 会尽量从 token 里解析账号信息。
- 这条导入链路固定按 ChatGPT/Codex OAuth 账号处理，不是通用 provider 导入接口。
- 如果你设置了 `issueVirtualKey: true`，会顺手生成一把可直接给客户使用的虚拟 key。
- 导入成功后，账号信息会写入服务端数据库，不是临时内存数据。
- 接口支持“部分成功”，所以不能只看 HTTP 状态码，还要看返回体里的 `importedCount`、`failedCount` 和 `results`。

一个典型返回体会长这样：

```json
{
  "success": false,
  "importedCount": 1,
  "failedCount": 1,
  "results": [
    {
      "index": 0,
      "success": true
    },
    {
      "index": 1,
      "success": false,
      "error": "access_token is required"
    }
  ]
}
```

## 7. 安全注意事项

这部分很重要。

- 公网导入必须走 HTTPS。
- 这个接口属于管理接口，不是给普通客户用的。
- 正常情况下必须带 `x-admin-token`。
- JSON 里可能包含 `access_token`、`refresh_token`、`id_token`，都属于高敏感凭据。
- 如果你把 `?admin_token=...` 直接带在 URL 里打开页面，页面会把它存进浏览器本地存储并从地址栏移除；建议只在受控的管理员设备上这样做。
- 服务器应配置 `OAUTH_APP_ENCRYPTION_KEY`，这样落盘的敏感凭据可以加密存储。
- 不要把这类 JSON 文件发给客户，也不要放到不受控的聊天群、网盘或工单系统里。

## 8. 常见失败和排查

### 8.1 返回 401 或 403

通常是下面几种原因：

- `x-admin-token` 没带。
- `x-admin-token` 错了。
- 你访问的不是管理接口地址。

先检查：

- 你是不是请求到了 `/api/accounts/import-json`
- 你是不是用了正确的管理令牌

### 8.2 返回 400

常见原因：

- JSON 不是合法 JSON。
- 缺少 `access_token` 或 `accessToken`。
- 一次导入超过 500 条。
- `email` 格式不合法。
- token 里既解析不出邮箱，也解析不出 `chatgpt_account_id`。
- 服务端启用了强制 workspace 限制，而这条账号不属于允许的 workspace。

建议先在 Windows 本地检查 JSON 是否能被正常解析。

### 8.3 浏览器里点了“导入 JSON 账号”但没成功

优先检查：

- 浏览器是不是已经拿到了管理令牌。
- 管理页是不是走 HTTPS。
- 选中的文件是不是标准 `.json`。
- 文件内容是不是对象或数组，而不是别的文本格式。

### 8.4 导入成功但没有生成虚拟 key

这是正常情况。JSON 导入时 `issueVirtualKey` 默认是 `false`。

如果你希望导入后自动生成虚拟 key，需要在每条记录里显式写：

```json
{
  "issueVirtualKey": true
}
```

## 9. 推荐操作顺序

如果你是人工偶尔导入，推荐这样做：

1. 先用浏览器方式导入。
2. 导入成功后到管理页确认账号状态。
3. 需要的话再单独签发虚拟 key，或者在 JSON 里加 `issueVirtualKey: true`。
4. 不要只看“请求成功”，还要确认返回结果里的失败条目是否为 0。

如果你是批量导入或周期性导入，推荐这样做：

1. 在 Windows 上准备好标准 JSON 文件。
2. 用 PowerShell 脚本调用 `/api/accounts/import-json`。
3. 记录响应结果，保留失败项。
4. 导入完成后再检查虚拟 key 和账号列表。

## 10. 一句话总结

部署后，远程 Windows 导入 JSON 账号文件的正确理解是：

Windows 本地读取文件，网关远程接收 JSON 内容，并通过管理接口把账号写入服务端数据库。
