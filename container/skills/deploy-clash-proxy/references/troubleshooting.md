# 代理综合排障

## 远端检查

```bash
sing-box check -c /etc/sing-box/config.json
systemctl status sing-box --no-pager
journalctl -u sing-box -n 50 --no-pager
ss -tulpn | grep ':443'
firewall-cmd --list-ports
```

## 常见问题

`Clash for Windows 连不上`

- 先确认服务端有 `tcp 443` 监听
- 再确认客户端使用的是 `trojan` 配置，而不是 `hysteria2`
- 检查云厂商安全组与 `firewalld` 是否都放行 `TCP/443`

`Clash Meta / Mihomo 连不上`

- 先确认服务端有 `udp 443` 监听
- 再确认客户端使用的是 `hysteria2` 配置
- 检查云厂商安全组与 `firewalld` 是否都放行 `UDP/443`

`证书错误`

- 无域名、自签证书场景下，客户端必须保留 `skip-cert-verify: true`
- `sni` 最好与证书 `CN/SAN` 一致

`服务能启动但无法转发`

- 检查远端默认路由和公网出站是否正常
- 检查系统时间是否准确
- 检查本机 ISP 是否屏蔽 UDP；如有必要，先退回 `trojan/TCP`

`Claude Code 能连 API，但登录失败`

- 如果 `api.anthropic.com` 返回 `401 invalid x-api-key`，说明 API 链路正常
- 再检查 `claude.ai/oauth/authorize` 是否返回 `403` 且带 `cf-mitigated: challenge`
- 如果是，优先怀疑出口 IP 被 Cloudflare challenge 或风控拦截
