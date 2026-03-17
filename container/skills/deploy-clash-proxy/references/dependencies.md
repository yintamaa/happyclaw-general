# 依赖

## 本机必须

- `bash`
- `curl`
- `openssl`
- `ssh`
- `scp`

## 本机建议

- `expect`
  用于只有密码、没有 SSH key 的场景
- `node`
  用于本机验证 `Claude Code` / TLS 行为
- `claude`
  用于实际测试 CLI
- `python3` + `PyYAML`
  仅在需要运行 `skill-creator` 自带的 `generate_openai_yaml.py` / `quick_validate.py` 时需要

## 远端

- `curl`
- `openssl`
- `systemd`
- `firewalld`

`sing-box` 由部署脚本自动安装，不要求用户预装。
