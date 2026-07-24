#!/usr/bin/env bash
# kimi-box — the OFFICIAL installer (code.kimi.com/install.sh): a uv-managed
# Python tool (kimi-cli), landing `kimi` in ~/.local/bin — uv's tool bin —
# with uv bringing its own managed CPython, so no apt python pin here (the
# mechanism's node stays claude/codex-only for the same reason). Run BY THE
# MECHANISM as root; the install itself runs AS the tenant user, never root:
# grok's lesson — a root-owned install under a 0700 home is a CLI that
# exists and cannot run.
set -euo pipefail

if [ ! -e "$TENANT_HOME/.local/bin/kimi" ]; then
  runuser -l "$TENANT_USER" -c 'curl -LsSf https://code.kimi.com/install.sh | bash'
fi
