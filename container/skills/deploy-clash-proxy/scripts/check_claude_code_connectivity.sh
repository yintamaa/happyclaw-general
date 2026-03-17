#!/usr/bin/env bash
set -euo pipefail

echo "[env]"
printf 'HTTP_PROXY=%s\n' "${HTTP_PROXY:-}"
printf 'HTTPS_PROXY=%s\n' "${HTTPS_PROXY:-}"
printf 'ALL_PROXY=%s\n' "${ALL_PROXY:-}"
printf 'SSL_CERT_FILE=%s\n' "${SSL_CERT_FILE:-}"
printf 'NODE_EXTRA_CA_CERTS=%s\n' "${NODE_EXTRA_CA_CERTS:-}"

echo
echo "[exit-ip]"
curl -s https://ipinfo.io/json || true

echo
echo "[api-root]"
curl -s -o /dev/null -w 'http_code=%{http_code}\n' https://api.anthropic.com || true

echo
echo "[api-auth]"
curl -s https://api.anthropic.com/v1/messages \
  -H 'x-api-key: test' \
  -H 'anthropic-version: 2023-06-01' \
  -H 'content-type: application/json' \
  -d '{}' || true

echo
echo "[node-tls]"
node -e "require('https').get('https://api.anthropic.com', r => { console.log('status', r.statusCode); r.resume(); }).on('error', e => { console.error('ERR', e.code, e.message); process.exit(1); })" || true

echo
echo "[oauth-authorize-head]"
curl -I -s 'https://claude.ai/oauth/authorize?code=true&client_id=9d1c250a-e61b-44d9-88ed-5944d1962f5e&response_type=code&redirect_uri=https%3A%2F%2Fplatform.claude.com%2Foauth%2Fcode%2Fcallback&scope=org%3Acreate_api_key+user%3Aprofile+user%3Ainference+user%3Asessions%3Aclaude_code+user%3Amcp_servers&code_challenge=test&code_challenge_method=S256&state=test' | sed -n '1,40p' || true
