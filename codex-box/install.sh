#!/usr/bin/env bash
# codex-box — the Codex CLI: the SCOPED @openai/codex npm global (verified
# upstream when the template was written), needing the Node 22+ the
# mechanism installed (NEEDS_NODE). Run BY THE MECHANISM as root — npm -g
# writes the global prefix, which is inherently root's on the nodesource
# layout; this is the install that keeps install.sh a root-run contract
# (rig#110's spec conflict, ruled on the issue).
set -euo pipefail

if ! command -v codex >/dev/null 2>&1; then
  npm install -g @openai/codex
fi
