#!/usr/bin/env bash
set -euo pipefail

REQUIRED_LOCAL=(bash curl openssl ssh scp)
OPTIONAL_LOCAL=(expect node claude)

echo "[required]"
for tool in "${REQUIRED_LOCAL[@]}"; do
  if command -v "$tool" >/dev/null 2>&1; then
    printf 'ok   %s -> %s\n' "$tool" "$(command -v "$tool")"
  else
    printf 'miss %s\n' "$tool"
  fi
done

echo
echo "[optional]"
for tool in "${OPTIONAL_LOCAL[@]}"; do
  if command -v "$tool" >/dev/null 2>&1; then
    printf 'ok   %s -> %s\n' "$tool" "$(command -v "$tool")"
  else
    printf 'miss %s\n' "$tool"
  fi
done
