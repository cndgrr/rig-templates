#!/usr/bin/env bash
# grok-box — the OFFICIAL installer (x.ai/cli/install.sh): installs the CLI
# as `grok`, a SYMLINK under $HOME/.grok/bin pointing into its versioned
# download dir. Run BY THE MECHANISM as root; the install itself runs AS the
# tenant user, never root — a symlink into root's 0700 home would be a CLI
# that exists and cannot run (this template's own scar, from the last drill).
set -euo pipefail

if [ ! -e "$TENANT_HOME/.grok/bin/grok" ]; then
  runuser -l "$TENANT_USER" -c 'curl -fsSL https://x.ai/cli/install.sh | bash'
fi
