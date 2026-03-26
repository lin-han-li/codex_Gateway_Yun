# Nginx Reverse Proxy

This directory contains an Ubuntu-friendly Nginx site example for Codex Gateway.

## What it does

- Terminates HTTPS on `443`
- Redirects all `80` traffic to HTTPS
- Proxies requests to the local gateway on `127.0.0.1:4777`
- Keeps SSE and streaming-friendly routes unbuffered for `/api/events*` and `/v1/*`
- Sets a small set of safe response headers

## Before enabling it

1. Replace `gateway.example.com` with your real domain.
2. Replace the certificate paths if you do not use Let's Encrypt.
3. Keep the Bun service bound locally or behind a firewall so clients reach Nginx, not port `4777` directly.

## Typical enable flow on Ubuntu

```bash
sudo cp codex-gateway.conf /etc/nginx/sites-available/codex-gateway.conf
sudo ln -s /etc/nginx/sites-available/codex-gateway.conf /etc/nginx/sites-enabled/codex-gateway.conf
sudo nginx -t
sudo systemctl reload nginx
```

## Certificate example

If you use Certbot with Nginx:

```bash
sudo apt-get install -y certbot python3-certbot-nginx
sudo certbot --nginx -d gateway.example.com
```

After Certbot updates the certificate paths, test and reload Nginx again.
