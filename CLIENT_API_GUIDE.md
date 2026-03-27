# Codex Gateway Client API Guide

This document explains how customers should call a deployed Codex Gateway.

## 1. Which address should clients use

After deployment, clients should call the same host and service port that exposes the gateway HTTP service:

- Recommended public access:
  - `https://gateway.example.com`
- Recommended private or LAN access:
  - `http://YOUR_SERVER_IP:4777`

Append `/v1` for business traffic:

- `https://gateway.example.com/v1`
- `http://YOUR_SERVER_IP:4777/v1`

Append `/api` for management traffic:

- `https://gateway.example.com/api`
- `http://YOUR_SERVER_IP:4777/api`

Important:

- Default application port is `4777`.
- If you put Nginx or Caddy in front, customers should usually call `443`, not `4777`.
- The optional built-in forward proxy port, usually `4778`, is not the OpenAI-compatible API port and should not be used by normal API clients.

## 2. Management APIs vs business APIs

There are two kinds of traffic:

- Management APIs under `/api/*`
  - Used by administrators to check health, create virtual keys, revoke keys, or sync OAuth credentials.
  - Usually require `x-admin-token`.
- Business APIs under `/v1/*`
  - Used by customers or client applications to send model requests through the gateway.
  - Require `Authorization: Bearer <virtual_key>`.

Authentication summary:

- `GET /api/health`
  - No `x-admin-token` required.
- Most other `/api/*`
  - Require `x-admin-token: YOUR_ADMIN_TOKEN`.
- `/v1/models`
  - Require `Authorization: Bearer YOUR_VIRTUAL_KEY`.
- `/v1/responses`
  - Require `Authorization: Bearer YOUR_VIRTUAL_KEY`.

## 3. Typical access flow after deployment

The normal flow is:

1. Administrator deploys the gateway.
2. Administrator imports or syncs one or more upstream accounts.
3. Administrator issues a virtual key.
4. Customer receives:
   - Gateway base URL, for example `https://gateway.example.com/v1`
   - Virtual key, for example `ocsk_live_...`
5. Customer sends OpenAI-compatible requests to the gateway using that base URL and virtual key.

## 4. Health check

Health check is the easiest way to test whether the service is reachable.

### curl

```bash
curl http://YOUR_SERVER_IP:4777/api/health
```

If you use HTTPS through a reverse proxy:

```bash
curl https://gateway.example.com/api/health
```

Expected response shape:

```json
{
  "ok": true,
  "name": "Codex Gateway"
}
```

## 5. Virtual key management

These endpoints are for administrators, not normal customers.

All examples below use:

- `GATEWAY_ORIGIN=https://gateway.example.com`
- `ADMIN_TOKEN=your_admin_token`

### 5.1 List virtual keys

### curl

```bash
curl "$GATEWAY_ORIGIN/api/virtual-keys" \
  -H "x-admin-token: $ADMIN_TOKEN"
```

You can also filter by account:

```bash
curl "$GATEWAY_ORIGIN/api/virtual-keys?accountId=ACCOUNT_ID" \
  -H "x-admin-token: $ADMIN_TOKEN"
```

### 5.2 Issue a virtual key

Request body fields:

- `accountId`
  - Optional for `pool` routing.
  - Usually required for `single` routing.
- `providerId`
  - Usually `chatgpt` or `openai`.
- `routingMode`
  - `single` or `pool`.
- `name`
  - Optional display name.
- `validityDays`
  - Optional expiration window.

### curl

```bash
curl "$GATEWAY_ORIGIN/api/virtual-keys/issue" \
  -X POST \
  -H "Content-Type: application/json" \
  -H "x-admin-token: $ADMIN_TOKEN" \
  -d '{
    "accountId": "ACCOUNT_ID",
    "providerId": "chatgpt",
    "routingMode": "single",
    "name": "Customer A Key",
    "validityDays": 30
  }'
```

Typical response:

```json
{
  "key": "ocsk_live_...",
  "record": {
    "id": "KEY_ID",
    "providerId": "chatgpt",
    "routingMode": "single"
  }
}
```

### 5.3 Revoke a virtual key

### curl

```bash
curl "$GATEWAY_ORIGIN/api/virtual-keys/KEY_ID/revoke" \
  -X POST \
  -H "x-admin-token: $ADMIN_TOKEN"
```

### 5.4 Rename a virtual key

### curl

```bash
curl "$GATEWAY_ORIGIN/api/virtual-keys/KEY_ID/name" \
  -X POST \
  -H "Content-Type: application/json" \
  -H "x-admin-token: $ADMIN_TOKEN" \
  -d '{
    "name": "Customer A Production Key"
  }'
```

### 5.5 Renew a virtual key

### curl

```bash
curl "$GATEWAY_ORIGIN/api/virtual-keys/KEY_ID/renew" \
  -X POST \
  -H "Content-Type: application/json" \
  -H "x-admin-token: $ADMIN_TOKEN" \
  -d '{
    "validityDays": 90
  }'
```

### 5.6 Reveal a virtual key

This is a sensitive action and needs both:

- `x-admin-token`
- `x-sensitive-action: confirm`

### curl

```bash
curl "$GATEWAY_ORIGIN/api/virtual-keys/KEY_ID/reveal" \
  -X POST \
  -H "x-admin-token: $ADMIN_TOKEN" \
  -H "x-sensitive-action: confirm"
```

## 6. OAuth bridge sync

If your own admin tooling already has upstream OAuth tokens, you can sync them into the gateway and optionally issue a virtual key in one call.

This is a management endpoint and requires `x-admin-token`.

### curl

```bash
curl "$GATEWAY_ORIGIN/api/bridge/oauth/sync" \
  -X POST \
  -H "Content-Type: application/json" \
  -H "x-admin-token: $ADMIN_TOKEN" \
  -d '{
    "providerId": "chatgpt",
    "providerName": "ChatGPT",
    "methodId": "codex-oauth",
    "email": "user@example.com",
    "accountId": "workspace_or_account_id",
    "accessToken": "ACCESS_TOKEN",
    "refreshToken": "REFRESH_TOKEN",
    "issueVirtualKey": true,
    "keyName": "Bridge Key"
  }'
```

Typical response:

```json
{
  "account": {
    "id": "ACCOUNT_ID"
  },
  "virtualKey": {
    "key": "ocsk_live_..."
  },
  "baseURL": "https://gateway.example.com/v1"
}
```

This response is useful because it gives you both:

- `baseURL`
- a ready-to-use `virtualKey`

## 6.1 Import JSON account files from a remote Windows machine

For a Chinese step-by-step operator guide dedicated to this workflow, see:

- `WINDOWS_REMOTE_JSON_IMPORT.md`

If an administrator is operating from Windows and the gateway is already deployed on Ubuntu or another server, the JSON account file can still be imported remotely.

Key point:

- The browser does not send a Windows file path to the server.
- The browser reads the selected local `.json` file on the Windows machine, parses it locally, then sends the JSON content to the gateway management API:
  - `POST /api/accounts/import-json`

This means remote import works as long as:

- the administrator can open the gateway management page
- the management request is authorized with `x-admin-token`
- the request is sent over HTTPS if the gateway is accessed across the Internet

### Browser workflow

1. Open the gateway management page:
   - `https://gateway.example.com/`
2. Make sure the browser already has the admin token, or open:
   - `https://gateway.example.com/?admin_token=YOUR_ADMIN_TOKEN`
3. Go to the account page and click:
   - `导入 JSON 账号`
4. Select one or more local `.json` files from the Windows machine.
5. The page reads those files locally and sends their parsed JSON content to:
   - `POST /api/accounts/import-json`

### Direct API workflow from Windows PowerShell

You can also bypass the web page and import directly from PowerShell:

```powershell
$json = Get-Content -Raw .\accounts.json

Invoke-RestMethod `
  -Uri "https://gateway.example.com/api/accounts/import-json" `
  -Method Post `
  -Headers @{
    "x-admin-token" = "YOUR_ADMIN_TOKEN"
    "Content-Type" = "application/json"
  } `
  -Body $json
```

If the file contains a single account object, send that object directly.
If the file contains multiple account records, send a JSON array.

### Accepted JSON shape

Each entry may contain fields such as:

- `email`
- `access_token` or `accessToken`
- `refresh_token` or `refreshToken`
- `id_token` or `idToken`
- `last_refresh` or `lastRefresh`
- `issueVirtualKey`
- `keyName`

Minimum practical requirement:

```json
{
  "email": "user@example.com",
  "access_token": "ACCESS_TOKEN"
}
```

`access_token` is required.
The importer will try to derive account metadata from token claims where possible.

## 7. Business API for customers

Customers should call the OpenAI-compatible endpoints under `/v1/*`.

Do not send `x-admin-token` for these business requests.
Send the virtual key as a Bearer token instead.

### 7.1 List models

### curl

```bash
curl "$GATEWAY_ORIGIN/v1/models" \
  -H "Authorization: Bearer $VIRTUAL_KEY"
```

Fetch one model:

```bash
curl "$GATEWAY_ORIGIN/v1/models/gpt-5" \
  -H "Authorization: Bearer $VIRTUAL_KEY"
```

### 7.2 Create a response

This is the main customer-facing request.

### curl

```bash
curl "$GATEWAY_ORIGIN/v1/responses" \
  -X POST \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $VIRTUAL_KEY" \
  -d '{
    "model": "gpt-5",
    "input": "Write a short hello from my deployed gateway."
  }'
```

You can also send a session-related key if you want stable routing in pool mode:

```bash
curl "$GATEWAY_ORIGIN/v1/responses" \
  -X POST \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $VIRTUAL_KEY" \
  -H "x-session-id: customer-session-001" \
  -d '{
    "model": "gpt-5",
    "input": "Continue this conversation."
  }'
```

Compact endpoint:

```bash
curl "$GATEWAY_ORIGIN/v1/responses/compact" \
  -X POST \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $VIRTUAL_KEY" \
  -d '{
    "model": "gpt-5",
    "input": "Return a concise answer."
  }'
```

## 8. OpenAI SDK examples

The gateway is intended to be used like an OpenAI-compatible endpoint.
The key points are:

- `baseURL` must point to your deployed gateway and include `/v1`
- `apiKey` must be the virtual key

### 8.1 Node.js

```javascript
import OpenAI from "openai";

const client = new OpenAI({
  apiKey: process.env.GATEWAY_VIRTUAL_KEY,
  baseURL: "https://gateway.example.com/v1"
});

const models = await client.models.list();
console.log(models.data.map((m) => m.id));

const response = await client.responses.create({
  model: "gpt-5",
  input: "Say hello from the gateway."
});

console.log(response.output_text);
```

### 8.2 Python

```python
from openai import OpenAI

client = OpenAI(
    api_key="YOUR_VIRTUAL_KEY",
    base_url="https://gateway.example.com/v1",
)

models = client.models.list()
print([m.id for m in models.data])

response = client.responses.create(
    model="gpt-5",
    input="Say hello from the gateway.",
)

print(response.output_text)
```

### 8.3 Raw HTTP client rules

If customers do not use the SDK, the rules are still simple:

- Management APIs:
  - Send to `/api/*`
  - Use `x-admin-token`
- Business APIs:
  - Send to `/v1/*`
  - Use `Authorization: Bearer <virtual_key>`

## 9. Which header to use

Use `x-admin-token` for:

- `/api/virtual-keys`
- `/api/virtual-keys/issue`
- `/api/virtual-keys/:id/name`
- `/api/virtual-keys/:id/renew`
- `/api/virtual-keys/:id/revoke`
- `/api/virtual-keys/:id/reveal`
- `/api/virtual-keys/:id`
- `/api/bridge/oauth/sync`
- almost all other `/api/*` management routes

Do not use `x-admin-token` as the customer request credential for model calls.

Use `Authorization: Bearer <virtual_key>` for:

- `/v1/models`
- `/v1/models/:id`
- `/v1/responses`
- `/v1/responses/compact`
- usage-style virtual-key routes such as `/wham/usage` or `/backend-api/codex/usage`

No auth header is required for:

- `/api/health`

Special sensitive header:

- `x-sensitive-action: confirm`
  - Required together with `x-admin-token` for key reveal operations

## 10. Recommended customer handoff

After you deploy the gateway, the cleanest handoff to a customer is:

- Base URL:
  - `https://gateway.example.com/v1`
- Virtual key:
  - `ocsk_live_...`
- One working curl command:

```bash
curl "https://gateway.example.com/v1/models" \
  -H "Authorization: Bearer ocsk_live_..."
```

- One working SDK snippet:

```javascript
const client = new OpenAI({
  apiKey: "ocsk_live_...",
  baseURL: "https://gateway.example.com/v1"
});
```

That is the main thing customers need.

## 11. Remote Ubuntu authorization options

When the gateway runs on a cloud Ubuntu server, do not assume the server can open a local desktop browser.

Recommended order:

1. `headless`
   - Start login from the server UI.
   - Open the returned OpenAI device URL on your local computer or phone.
   - Enter the user code shown by the gateway.
   - The server will poll and complete the login without a localhost browser callback.
2. `manual-code`
   - Start login from the server UI.
   - Open the authorization URL on your local browser.
   - After OpenAI redirects, copy the full callback URL or just the `code` value back into the server UI.
3. `browser`
   - Only use this when the browser really runs on the same machine as the gateway.
   - If you start this from a remote browser, OpenAI usually redirects to that browser machine's `localhost`, not the Ubuntu server.

## 12. Import refresh-token credentials directly

The gateway now supports `POST /api/accounts/import-rt`.

Use this when you already have a `refresh_token` and want the server to create or repair an OAuth account without opening a browser.

Minimal payload:

```json
{
  "refresh_token": "YOUR_REFRESH_TOKEN"
}
```

Better payload:

```json
{
  "refresh_token": "YOUR_REFRESH_TOKEN",
  "access_token": "OPTIONAL_ACCESS_TOKEN",
  "account_id": "OPTIONAL_CHATGPT_ACCOUNT_ID",
  "email": "optional@example.com",
  "issueVirtualKey": false
}
```

Behavior:

- If `access_token` is present, the gateway stores it directly.
- If `access_token` is missing, the gateway tries to refresh it first by using the supplied `refresh_token`.
- The route returns `importedCount`, `failedCount`, `refreshedCount`, and per-record results.

## 13. Export accounts from a local desktop and import on Ubuntu

For many teams this is the safest workflow:

1. Log in on a Windows desktop where browser OAuth is easy.
2. Use the desktop UI button `导出 JSON 账号`, or call `POST /api/accounts/export-json`.
3. Copy the exported `accounts_YYYYMMDD_HHMMSS.json` file to the Ubuntu server.
4. In the server UI use `导入 JSON 账号`, or call `POST /api/accounts/import-json`.

`POST /api/accounts/export-json` requires `x-sensitive-action: confirm` because the exported file contains live credentials.
