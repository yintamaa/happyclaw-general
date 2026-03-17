#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  bootstrap_claude_code_env.sh [options]

Options:
  --http-proxy URL     HTTP proxy URL
  --https-proxy URL    HTTPS proxy URL
  --all-proxy URL      ALL_PROXY URL
  --zshrc PATH         zshrc path, default: ~/.zshrc
EOF
}

ZSHRC_PATH="${HOME}/.zshrc"
HTTP_PROXY_VALUE=""
HTTPS_PROXY_VALUE=""
ALL_PROXY_VALUE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --http-proxy) HTTP_PROXY_VALUE="${2:-}"; shift 2 ;;
    --https-proxy) HTTPS_PROXY_VALUE="${2:-}"; shift 2 ;;
    --all-proxy) ALL_PROXY_VALUE="${2:-}"; shift 2 ;;
    --zshrc) ZSHRC_PATH="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown arg: $1" >&2; usage; exit 1 ;;
  esac
done

touch "$ZSHRC_PATH"
TMP_FILE="$(mktemp)"
trap 'rm -f "$TMP_FILE"' EXIT

awk '
  BEGIN {skip=0}
  /# >>> claude-proxy-bootstrap >>>/ {skip=1; next}
  /# <<< claude-proxy-bootstrap <<</ {skip=0; next}
  skip==0 {print}
' "$ZSHRC_PATH" >"$TMP_FILE"

{
  cat "$TMP_FILE"
  printf '\n# >>> claude-proxy-bootstrap >>>\n'
  printf 'export SSL_CERT_FILE="/private/etc/ssl/cert.pem"\n'
  printf 'export NODE_EXTRA_CA_CERTS="/private/etc/ssl/cert.pem"\n'
  if [[ -n "$HTTP_PROXY_VALUE" ]]; then
    printf 'export HTTP_PROXY="%s"\n' "$HTTP_PROXY_VALUE"
  fi
  if [[ -n "$HTTPS_PROXY_VALUE" ]]; then
    printf 'export HTTPS_PROXY="%s"\n' "$HTTPS_PROXY_VALUE"
  fi
  if [[ -n "$ALL_PROXY_VALUE" ]]; then
    printf 'export ALL_PROXY="%s"\n' "$ALL_PROXY_VALUE"
  fi
  printf '# <<< claude-proxy-bootstrap <<<\n'
} >"$ZSHRC_PATH"

echo "Updated ${ZSHRC_PATH}"
echo
echo "Run one of:"
echo "  source ${ZSHRC_PATH}"
echo "  exec zsh"
