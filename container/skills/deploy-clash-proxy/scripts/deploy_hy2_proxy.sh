#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  deploy_hy2_proxy.sh --host HOST [options]

Required:
  --host HOST                    Remote host or IP

Optional:
  --ssh-user USER                SSH user, default: root
  --ssh-port PORT                SSH port, default: 22
  --root-password PASSWORD       SSH password; if omitted, use current SSH agent/key
  --server-name NAME             TLS server name / cert SAN, default: host
  --proxy-port PORT              Hysteria2 port, default: 443
  --name NODE_NAME               Clash node name, default: host-hy2
  --up-mbps NUM                  Server advertised uplink Mbps, default: 200
  --down-mbps NUM                Server advertised downlink Mbps, default: 200
  --auth-password PASSWORD       HY2 auth password; random if omitted
  --obfs-password PASSWORD       Salamander obfs password; random if omitted
  --output PATH                  Save Clash Meta YAML to path
EOF
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing command: $1" >&2
    exit 1
  }
}

random_b64() {
  openssl rand -base64 24 | tr -d '\n'
}

random_hex() {
  openssl rand -hex 16
}

HOST=""
SSH_USER="root"
SSH_PORT="22"
ROOT_PASSWORD=""
SERVER_NAME=""
PROXY_PORT="443"
NODE_NAME=""
UP_MBPS="200"
DOWN_MBPS="200"
AUTH_PASSWORD=""
OBFS_PASSWORD=""
OUTPUT_PATH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host) HOST="${2:-}"; shift 2 ;;
    --ssh-user) SSH_USER="${2:-}"; shift 2 ;;
    --ssh-port) SSH_PORT="${2:-}"; shift 2 ;;
    --root-password) ROOT_PASSWORD="${2:-}"; shift 2 ;;
    --server-name) SERVER_NAME="${2:-}"; shift 2 ;;
    --proxy-port) PROXY_PORT="${2:-}"; shift 2 ;;
    --name) NODE_NAME="${2:-}"; shift 2 ;;
    --up-mbps) UP_MBPS="${2:-}"; shift 2 ;;
    --down-mbps) DOWN_MBPS="${2:-}"; shift 2 ;;
    --auth-password) AUTH_PASSWORD="${2:-}"; shift 2 ;;
    --obfs-password) OBFS_PASSWORD="${2:-}"; shift 2 ;;
    --output) OUTPUT_PATH="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown arg: $1" >&2; usage; exit 1 ;;
  esac
done

if [[ -z "$HOST" ]]; then
  usage
  exit 1
fi

require_cmd openssl
require_cmd ssh

if [[ -n "$ROOT_PASSWORD" ]]; then
  require_cmd expect
fi

SERVER_NAME="${SERVER_NAME:-$HOST}"
NODE_NAME="${NODE_NAME:-${HOST}-hy2}"
AUTH_PASSWORD="${AUTH_PASSWORD:-$(random_b64)}"
OBFS_PASSWORD="${OBFS_PASSWORD:-$(random_hex)}"
OUTPUT_PATH="${OUTPUT_PATH:-./${HOST}-clash-meta.yaml}"

SSH_BASE=(ssh -p "$SSH_PORT" -o StrictHostKeyChecking=no "${SSH_USER}@${HOST}")
SCP_BASE=(scp -P "$SSH_PORT" -o StrictHostKeyChecking=no)
REMOTE_TMP="/tmp/deploy-hy2-$$.sh"
LOCAL_TMP="$(mktemp)"
trap 'rm -f "$LOCAL_TMP"' EXIT

cat >"$LOCAL_TMP" <<EOF
set -euo pipefail
mkdir -p /etc/sing-box /var/lib/sing-box /etc/pki/sing-box
if ! command -v sing-box >/dev/null 2>&1; then
  curl -fsSL https://sing-box.app/install.sh | sh
fi
openssl req -x509 -nodes -newkey rsa:2048 -days 3650 \
  -keyout /etc/pki/sing-box/server.key \
  -out /etc/pki/sing-box/server.crt \
  -subj '/CN=${SERVER_NAME}' \
  -addext 'subjectAltName = DNS:${SERVER_NAME},IP:${HOST}' >/dev/null 2>&1 || \
openssl req -x509 -nodes -newkey rsa:2048 -days 3650 \
  -keyout /etc/pki/sing-box/server.key \
  -out /etc/pki/sing-box/server.crt \
  -subj '/CN=${SERVER_NAME}'
cat > /etc/sing-box/config.json <<'JSON'
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "hysteria2",
      "tag": "hy2-in",
      "listen": "::",
      "listen_port": ${PROXY_PORT},
      "up_mbps": ${UP_MBPS},
      "down_mbps": ${DOWN_MBPS},
      "obfs": {
        "type": "salamander",
        "password": "${OBFS_PASSWORD}"
      },
      "users": [
        {
          "name": "clash",
          "password": "${AUTH_PASSWORD}"
        }
      ],
      "ignore_client_bandwidth": false,
      "tls": {
        "enabled": true,
        "server_name": "${SERVER_NAME}",
        "alpn": ["h3"],
        "certificate_path": "/etc/pki/sing-box/server.crt",
        "key_path": "/etc/pki/sing-box/server.key"
      },
      "masquerade": {
        "type": "string",
        "status_code": 200,
        "headers": {
          "content-type": ["text/plain; charset=utf-8"]
        },
        "content": "ok"
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ]
}
JSON
sing-box check -c /etc/sing-box/config.json
systemctl enable --now sing-box
firewall-cmd --permanent --add-port=${PROXY_PORT}/udp >/dev/null
firewall-cmd --permanent --add-port=${PROXY_PORT}/tcp >/dev/null || true
firewall-cmd --reload >/dev/null
systemctl --no-pager --full status sing-box | sed -n '1,14p'
printf '\n---\n'
ss -u -lpn | grep ':${PROXY_PORT}' || true
EOF

run_remote() {
  if [[ -n "$ROOT_PASSWORD" ]]; then
    expect <<EOF
set timeout 240
spawn ${SCP_BASE[*]} "$LOCAL_TMP" ${SSH_USER}@${HOST}:${REMOTE_TMP}
expect {
  "*yes/no*" { send "yes\r"; exp_continue }
  "*password:*" { send "${ROOT_PASSWORD}\r" }
}
expect eof
EOF
    expect <<EOF
set timeout 240
spawn ${SSH_BASE[*]} "bash ${REMOTE_TMP} && rm -f ${REMOTE_TMP}"
expect {
  "*yes/no*" { send "yes\r"; exp_continue }
  "*password:*" { send "${ROOT_PASSWORD}\r" }
}
expect eof
EOF
  else
    "${SSH_BASE[@]}" "bash -s" <"$LOCAL_TMP"
  fi
}

echo "Deploying Hysteria2 to ${SSH_USER}@${HOST}:${SSH_PORT}"
run_remote

cat >"$OUTPUT_PATH" <<EOF
proxies:
  - name: "${NODE_NAME}"
    type: hysteria2
    server: ${HOST}
    port: ${PROXY_PORT}
    password: ${AUTH_PASSWORD}
    obfs: salamander
    obfs-password: ${OBFS_PASSWORD}
    up: "${UP_MBPS} Mbps"
    down: "${DOWN_MBPS} Mbps"
    sni: ${SERVER_NAME}
    skip-cert-verify: true
    alpn:
      - h3
    udp: true
proxy-groups:
  - name: PROXY
    type: select
    proxies:
      - "${NODE_NAME}"
rules:
  - MATCH,PROXY
EOF

echo
echo "Client config saved to ${OUTPUT_PATH}"
echo "Auth password: ${AUTH_PASSWORD}"
echo "Obfs password: ${OBFS_PASSWORD}"
echo
cat "$OUTPUT_PATH"
