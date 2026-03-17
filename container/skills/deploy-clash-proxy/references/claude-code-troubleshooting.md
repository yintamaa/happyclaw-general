# Claude Code 排障

## 快速判断

`UNABLE_TO_GET_ISSUER_CERT_LOCALLY`

- 根因通常是 `Node` 没有使用系统 CA
- 在 `~/.zshrc` 写入：

```bash
export SSL_CERT_FILE="/private/etc/ssl/cert.pem"
export NODE_EXTRA_CA_CERTS="/private/etc/ssl/cert.pem"
```

`ERR_BAD_REQUEST`

- 如果 `api.anthropic.com` 能返回 `401 invalid x-api-key`，说明 API 链路正常
- 再检查 `claude.ai/oauth/authorize` 是否返回 `403` 且带 `cf-mitigated: challenge`
- 如果是，重点怀疑出口 IP 被 Cloudflare challenge 拦截

`curl` 显示本地 IP

- 当前 shell 没有加载代理变量
- 用户若使用 `zsh`，不要只写 `~/.bashrc`
- 应把代理写到 `~/.zshrc`

## 推荐命令

```bash
env | grep -i proxy
curl -s https://ipinfo.io/json
node -e "require('https').get('https://api.anthropic.com', r => console.log(r.statusCode)).on('error', console.error)"
claude auth status
```
