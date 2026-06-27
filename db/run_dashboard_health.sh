#!/usr/bin/env bash
set -euo pipefail

echo "=== jobpush-dashboard.service ==="
systemctl status jobpush-dashboard.service --no-pager || true

echo
echo "=== recent dashboard logs ==="
journalctl -u jobpush-dashboard.service --no-pager -n 160 || true
