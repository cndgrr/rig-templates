#!/usr/bin/env bash
# claude-box — the Claude Code CLI, plus the shell niceties the box template
# shipped (zsh login shell, oh-my-zsh, tmux mouse mode). Run BY THE MECHANISM
# as root, with TENANT_USER/TENANT_HOME/TENANT_GROUP/ROLE exported (rig#110);
# the CLI itself lands AS the tenant user — a root-owned install under a 0700
# home is a CLI that exists and cannot run (the grok-box template's scar).
set -euo pipefail

if [ ! -e "$TENANT_HOME/.local/bin/claude" ]; then
  runuser -l "$TENANT_USER" -c 'curl -fsSL https://claude.ai/install.sh | bash'
fi

# --- shell niceties -----------------------------------------------------------
# Cosmetic EXTRAS: oh-my-zsh's failure warns, never aborts an install whose
# real work (the CLI) already landed. zsh itself arrives via APT_EXTRAS
# before this script runs; the login-shell flip is root's, which is why the
# mechanism hands this script root and the tenant's name rather than running
# it AS the tenant.
if [ "$(getent passwd "$TENANT_USER" | cut -d: -f7)" != "/usr/bin/zsh" ]; then
  chsh -s /usr/bin/zsh "$TENANT_USER"
fi
if [ ! -d "$TENANT_HOME/.oh-my-zsh" ]; then
  # Single quotes on purpose: the $(...) must run in the USER's shell.
  # shellcheck disable=SC2016
  runuser -l "$TENANT_USER" -c 'RUNZSH=no CHSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"' \
    || echo "claude-box install: WARNING: oh-my-zsh install failed — cosmetic only; continuing" >&2
fi
# After oh-my-zsh (it rewrites .zshrc on first install): the rc lines,
# appended once, ownership converged to the tenant.
append_once() {
  if [ ! -e "$1" ] || ! grep -qxF "$2" "$1"; then printf '%s\n' "$2" >> "$1"; fi
  chown "$TENANT_USER:$TENANT_GROUP" "$1"
}
# shellcheck disable=SC2016  # the line must expand in the USER's shell, not here
append_once "$TENANT_HOME/.zshrc" 'export PATH="$HOME/.local/bin:$PATH"'
append_once "$TENANT_HOME/.tmux.conf" 'set -g mouse on'
