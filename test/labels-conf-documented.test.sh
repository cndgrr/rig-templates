#!/usr/bin/env bash
# labels-conf-documented.test.sh — prove the documentation/config set check
# green on the registry and red, with a diagnosis, on each divergence.
#
# A check nobody has watched fail is a check nobody knows fires. Each negative
# asserts the message as well as the exit code.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK="$ROOT/test/labels-conf-documented.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

failures=0
report() { printf 'labels-conf-documented.test: %s\n' "$*"; }
fail() { printf 'labels-conf-documented.test: FAIL — %s\n' "$*" >&2; failures=$((failures + 1)); }

fixture() {
  local dir="$TMP/$1"
  mkdir -p "$dir/.github"
  cp "$ROOT/CONTRIBUTING.md" "$dir/CONTRIBUTING.md"
  cp "$ROOT/.github/labels.conf" "$dir/.github/labels.conf"
  printf '%s\n' "$dir"
}

expect_green() {
  local name="$1" dir="$2" log="$TMP/$1.log"
  if bash "$CHECK" "$dir" >"$log" 2>&1; then
    report "PASS — $name is green"
  else
    fail "$name should be green; the check said: $(cat "$log")"
  fi
}

expect_red() {
  local name="$1" dir="$2" expected="$3" log="$TMP/$1.log"
  if bash "$CHECK" "$dir" >"$log" 2>&1; then
    fail "$name should be red; the check passed it"
    return
  fi
  if grep -qF "$expected" "$log"; then
    report "PASS — $name is red, and says so: $(head -1 "$log")"
  else
    fail "$name is red but the message never mentions '$expected'; it said: $(cat "$log")"
  fi
}

expect_green real-registry "$ROOT"

doc_bot="$(fixture doc-extra-bot)"
sed -i '/`kimi-bot-andresmgsl`/s/`kimi-bot/`grok-bot-andresmgsl`, `kimi-bot/' \
  "$doc_bot/CONTRIBUTING.md"
expect_red doc-extra-bot "$doc_bot" 'grok-bot-andresmgsl'

config_bot="$(fixture config-extra-bot)"
sed -i '/^panel=/s/$/ grok-bot-andresmgsl/' "$config_bot/.github/labels.conf"
expect_red config-extra-bot "$config_bot" 'grok-bot-andresmgsl'

config_scope="$(fixture config-extra-scope)"
printf '%s\n' 'scope:docs|C5DEF5|documentation' >>"$config_scope/.github/labels.conf"
expect_red config-extra-scope "$config_scope" 'scope:docs'

doc_scope="$(fixture doc-extra-scope)"
sed -i 's/`scope:ci`/`scope:ci`, `scope:docs`/' "$doc_scope/CONTRIBUTING.md"
expect_red doc-extra-scope "$doc_scope" 'scope:docs'

# A future per-actor override may legitimately differ from the default panel.
# Prove the exact panel= parser does not swallow panel[<actor>]= rows.
override="$(fixture divergent-override)"
printf '%s\n' 'panel[next-builder]=grok-bot-andresmgsl' >>"$override/.github/labels.conf"
expect_green divergent-override "$override"

# Membership is the contract. Reordering the data must not make prose drift.
reordered="$(fixture reordered-panel)"
sed -i 's/^panel=.*/panel=kimi-bot-andresmgsl claude-bot-andresmgsl codex-bot-andresmgsl/' \
  "$reordered/.github/labels.conf"
expect_green reordered-panel "$reordered"

if [ "$failures" -ne 0 ]; then
  printf 'labels-conf-documented.test: %s assertion(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'labels-conf-documented.test: every assertion passed\n'
