#!/usr/bin/env bash
set -euo pipefail
pkill -f "go run cmd/main.go" || true
docker rm -f pd-mysql >/dev/null 2>&1 || true
echo "Parado."
