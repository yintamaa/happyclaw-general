#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  deploy_dual_stack_proxy.sh --host HOST [options]

Required:
  --host HOST                    Remote host or IP

Optional:
  --ssh-user USER                SSH user, default: root
  --ssh-port PORT                SSH port, default: 22
  --root-password PASSWORD       SSH password; if omitted, use current SSH agent/key
  --server-name NAME             TLS server name / cert SAN, default: host
  --proxy-port PORT              Shared proxy port, default: 443
  --name NODE_PREFIX             Node prefix, default: host
  --up-mbps NUM                  Hysteria2 uplink Mbps, default: 200
  --down-mbps NUM                Hysteria2 downlink Mbps, default: 200
  --trojan-password PASSWORD     Trojan password; random if omitted
  --hy2-auth PASSWORD            Hysteria2 auth password; random if omitted
  --hy2-obfs PASSWORD            Hysteria2 obfs password; random if omitted
  --output-dir PATH              Output directory for YAMLs, default: current directory
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
TROJAN_PASSWORD=""
HY2_AUTH=""
HY2_OBFS=""
OUTPUT_DIR="."

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
    --trojan-password) TROJAN_PASSWORD="${2:-}"; shift 2 ;;
    --hy2-auth) HY2_AUTH="${2:-}"; shift 2 ;;
    --hy2-obfs) HY2_OBFS="${2:-}"; shift 2 ;;
    --output-dir) OUTPUT_DIR="${2:-}"; shift 2 ;;
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
require_cmd scp
require_cmd mkdir
require_cmd sed
if [[ -n "$ROOT_PASSWORD" ]]; then
  require_cmd expect
fi

SERVER_NAME="${SERVER_NAME:-$HOST}"
NODE_NAME="${NODE_NAME:-$HOST}"
TROJAN_PASSWORD="${TROJAN_PASSWORD:-$(random_b64)}"
HY2_AUTH="${HY2_AUTH:-$(random_b64)}"
HY2_OBFS="${HY2_OBFS:-$(random_hex)}"

mkdir -p "$OUTPUT_DIR"

SSH_BASE=(ssh -p "$SSH_PORT" -o StrictHostKeyChecking=no "${SSH_USER}@${HOST}")
SCP_BASE=(scp -P "$SSH_PORT" -o StrictHostKeyChecking=no)
REMOTE_TMP="/tmp/deploy-dual-proxy-$$.sh"
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
        "password": "${HY2_OBFS}"
      },
      "users": [
        {
          "name": "clash",
          "password": "${HY2_AUTH}"
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
    },
    {
      "type": "trojan",
      "tag": "trojan-in",
      "listen": "::",
      "listen_port": ${PROXY_PORT},
      "users": [
        {
          "password": "${TROJAN_PASSWORD}"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "${SERVER_NAME}",
        "certificate_path": "/etc/pki/sing-box/server.crt",
        "key_path": "/etc/pki/sing-box/server.key"
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
firewall-cmd --permanent --add-port=${PROXY_PORT}/tcp >/dev/null || true
firewall-cmd --permanent --add-port=${PROXY_PORT}/udp >/dev/null || true
firewall-cmd --reload >/dev/null
systemctl --no-pager --full status sing-box | sed -n '1,14p'
printf '\n---\n'
ss -tulpn | grep ':${PROXY_PORT}' || true
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

echo "Deploying dual-stack proxy to ${SSH_USER}@${HOST}:${SSH_PORT}"
run_remote

TROJAN_FILE="${OUTPUT_DIR%/}/${NODE_NAME}-trojan-cfw.yaml"
HY2_FILE="${OUTPUT_DIR%/}/${NODE_NAME}-hy2-meta.yaml"

cat >"$TROJAN_FILE" <<EOF
proxies:
  - name: "${NODE_NAME}-trojan"
    type: trojan
    server: ${HOST}
    port: ${PROXY_PORT}
    password: "${TROJAN_PASSWORD}"
    sni: ${SERVER_NAME}
    skip-cert-verify: true
    udp: true
proxy-groups:
  - name: PROXY
    type: select
    proxies:
      - "${NODE_NAME}-trojan"
rules:
  - MATCH,PROXY
EOF

cat >"$HY2_FILE" <<EOF
proxies:
  - name: "${NODE_NAME}-hy2"
    type: hysteria2
    server: ${HOST}
    port: ${PROXY_PORT}
    password: ${HY2_AUTH}
    obfs: salamander
    obfs-password: ${HY2_OBFS}
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
      - "${NODE_NAME}-hy2"
rules:
  - MATCH,PROXY
EOF

echo
echo "Trojan YAML: ${TROJAN_FILE}"
echo "Hysteria2 YAML: ${HY2_FILE}"
echo "Trojan password: ${TROJAN_PASSWORD}"
echo "HY2 auth password: ${HY2_AUTH}"
echo "HY2 obfs password: ${HY2_OBFS}"
