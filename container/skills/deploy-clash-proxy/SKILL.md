---
name: deploy-clash-proxy
description: >
  在海外 Linux 主机上部署可被 Clash for Windows、Clash Meta、Mihomo 使用的代理节点，
  并修复本机 shell、证书链、Claude Code 登录与连通性问题。用户提供 VPS/云主机、
  SSH 凭据，要求“搭代理”“给 clash 用”“部署 trojan 或 hysteria2”“让 Claude Code 走代理”
  或要求把整套部署与排障流程沉淀成 skill 时使用。
---

# 部署 Clash 代理

优先使用双协议方案：远端 `sing-box` 同时提供

- `trojan/TCP 443`，兼容旧版 Clash for Windows
- `hysteria2/UDP 443`，兼容 Clash Meta / Mihomo

无域名时默认使用自签证书，并在客户端保留 `skip-cert-verify: true`。

## 执行顺序

1. 运行 [check_dependencies.sh](./scripts/check_dependencies.sh) 确认本机依赖。
2. 用 [deploy_dual_stack_proxy.sh](./scripts/deploy_dual_stack_proxy.sh) 部署双协议节点。
3. 如果用户只需要 Mihomo/Meta，可继续使用 [deploy_hy2_proxy.sh](./scripts/deploy_hy2_proxy.sh) 的单协议方案。
4. 用 [bootstrap_claude_code_env.sh](./scripts/bootstrap_claude_code_env.sh) 把代理变量和 Node CA 修复写入 `~/.zshrc`。
5. 用 [check_claude_code_connectivity.sh](./scripts/check_claude_code_connectivity.sh) 区分“没走代理”“证书链错误”“出口 IP 被 `claude.ai` 风控”。

## 何时选哪条路径

- 用户是老 `Clash for Windows`：优先给 `trojan` 配置
- 用户是 Clash Meta / Mihomo：优先给 `hysteria2` 配置
- 用户既要兼容旧客户端，又想保留更现代协议：部署双协议
- 用户说 `curl` 是本地 IP、`claude` 不走代理：先修 `~/.zshrc`
- 用户看到 `UNABLE_TO_GET_ISSUER_CERT_LOCALLY`：先修 `SSL_CERT_FILE` 与 `NODE_EXTRA_CA_CERTS`
- 用户看到 `ERR_BAD_REQUEST`，但 `api.anthropic.com` 能返回 `401 invalid x-api-key`：重点怀疑 `claude.ai` OAuth 登录页被 Cloudflare challenge 或地区风控拦截

## 核心脚本

部署双协议：

```bash
container/skills/deploy-clash-proxy/scripts/deploy_dual_stack_proxy.sh \
  --host 203.0.113.10 \
  --ssh-user root \
  --root-password 'your-password' \
  --name 'tokyo'
```

写入本机 shell 与证书修复：

```bash
container/skills/deploy-clash-proxy/scripts/bootstrap_claude_code_env.sh \
  --http-proxy http://127.0.0.1:7890 \
  --https-proxy http://127.0.0.1:7890 \
  --all-proxy socks5://127.0.0.1:7891
```

检查 Claude Code 连通性：

```bash
container/skills/deploy-clash-proxy/scripts/check_claude_code_connectivity.sh
```

## 输出约定

双协议脚本会输出：

- 远端服务状态
- `trojan` 密码
- `hysteria2` 的 auth 与 obfs 密码
- `Clash for Windows` 用的 YAML
- `Clash Meta / Mihomo` 用的 YAML

本机初始化脚本会输出：

- `~/.zshrc` 是否已写入代理变量
- `SSL_CERT_FILE` 与 `NODE_EXTRA_CA_CERTS` 是否已写入
- 下一步该执行 `source ~/.zshrc` 还是直接开新终端

连通性检查脚本会区分：

- shell 当前是否加载代理变量
- `curl` 是否真的走代理
- `Node` 到 `api.anthropic.com` 是否存在 CA 错误
- `claude.ai/oauth/authorize` 是否返回 Cloudflare challenge

## 参考文件

- Clash Meta 配置模板：看 [clash-meta-template.yaml](./references/clash-meta-template.yaml)
- Clash for Windows 配置模板：看 [clash-for-windows-trojan.yaml](./references/clash-for-windows-trojan.yaml)
- 综合排障：看 [troubleshooting.md](./references/troubleshooting.md)
- Claude Code 诊断要点：看 [claude-code-troubleshooting.md](./references/claude-code-troubleshooting.md)
- 本机与远端依赖：看 [dependencies.md](./references/dependencies.md)
