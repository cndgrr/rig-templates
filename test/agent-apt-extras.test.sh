#!/usr/bin/env bash
# agent-apt-extras.test.sh — drives test/agent-apt-extras.sh against the real
# registry and against fixtures of every way the contract can be broken.
#
# A check nobody has watched fail is a check nobody knows fires. Each negative
# below asserts the MESSAGE too, so a refactor that keeps the exit code and
# loses the diagnosis is caught here rather than on the box.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK="$ROOT/test/agent-apt-extras.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

failures=0
report() { printf 'agent-apt-extras.test: %s\n' "$*"; }
fail() { printf 'agent-apt-extras.test: FAIL — %s\n' "$*" >&2; failures=$((failures + 1)); }

# A fixture is a fresh copy of the registry's box definitions, mutated one way.
fixture() {
  local dir="$TMP/$1"
  mkdir -p "$dir"
  cp -R "$ROOT"/*-box "$dir/"
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

# --- The registry as it stands ---------------------------------------------
if bash "$CHECK" "$ROOT" >"$TMP/registry.log" 2>&1; then
  report "PASS — the real registry is green"
else
  fail "the real registry is red: $(cat "$TMP/registry.log")"
fi

# The tenant set is DERIVED, so prove the derivation and not just its result:
# the four vendor tenants are bound to the base, and staging-box's AGENT="no"
# is what keeps an agentless *-box out of it.
for tenant in claude-box codex-box grok-box kimi-box; do
  grep -q "$tenant" "$TMP/registry.log" \
    || fail "$tenant is not in the checked tenant set: $(cat "$TMP/registry.log")"
done
if grep -q 'staging-box' "$TMP/registry.log"; then
  fail "staging-box declares AGENT=\"no\" and must not be held to the agent base"
else
  report 'PASS — staging-box (AGENT="no") is excluded from the agent base'
fi

# --- Base divergence: the drift the check exists to catch -------------------
dropped="$(fixture drop-gh)"
sed -i 's/^APT_EXTRAS="cron gh jq"$/APT_EXTRAS="cron jq"/' "$dropped/grok-box/template.env"
expect_red drop-gh "$dropped" "drops shared base package 'gh'"

missing="$(fixture no-apt-extras)"
sed -i '/^APT_EXTRAS=/d' "$missing/kimi-box/template.env"
expect_red no-apt-extras "$missing" "declares no APT_EXTRAS"

doubled="$(fixture two-apt-extras)"
printf 'APT_EXTRAS="cron gh jq tmux"\n' >>"$doubled/codex-box/template.env"
expect_red two-apt-extras "$doubled" "declares APT_EXTRAS 2 times"

# --- A vendor addition is an ordinary, allowed act --------------------------
vendored="$(fixture vendor-addition)"
sed -i 's/^APT_EXTRAS="cron gh jq"$/APT_EXTRAS="cron gh jq tmux"/' "$vendored/codex-box/template.env"
expect_green vendor-addition "$vendored"

# --- The ownership boundary -------------------------------------------------
engine="$(fixture duty-engine)"
# shellcheck disable=SC2016  # the fixture must write the literal tenant path
printf '\ninstall -d "$HOME/duty"\n' >>"$engine/claude-box/install.sh"
expect_red duty-engine "$engine" "installs crew's duty engine"

hired="$(fixture crew-hire)"
# shellcheck disable=SC2016  # the fixture must write the literal tenant name
printf '\ncrew hire "$USER"\n' >>"$hired/kimi-box/install.sh"
expect_red crew-hire "$hired" "installs crew's duty engine"

# The boundary may be DOCUMENTED without being tripped: a comment naming the
# engine tree is prose, not an install, and a check that reds on it teaches
# authors to stop explaining themselves.
documented="$(fixture documented-boundary)"
printf '\n# crew owns ~/duty and crew upgrade writes it; this hook never does.\n' \
  >>"$documented/codex-box/install.sh"
expect_green documented-boundary "$documented"

flavoured="$(fixture crew-vendor-role)"
mkdir -p "$flavoured/crew-kimi-box"
cp "$ROOT/kimi-box/template.env" "$ROOT/kimi-box/install.sh" "$flavoured/crew-kimi-box/"
expect_red crew-vendor-role "$flavoured" "crew membership is a package list"

if [ "$failures" -ne 0 ]; then
  printf 'agent-apt-extras.test: %s assertion(s) failed\n' "$failures" >&2
  exit 1
fi
printf 'agent-apt-extras.test: every assertion passed\n'
