#!/usr/bin/env bash
# labels-conf-documented.sh — hold this registry's documented panel and scope
# sets against the data that drives its automation.
#
# CONTRIBUTING.md deliberately names the default review panel for readers;
# .github/labels.conf's unqualified panel= row is what the state machine reads.
# Per-actor panel[<actor>]= overrides are excluded: CONTRIBUTING.md does not
# document them, and this repository has not defined what a divergent override
# should mean in the default-panel prose.
#
# Scope names likewise live in both files by design. Compare memberships, not
# order or formatting: those are prose choices rather than registry contracts.
#
# usage: bash test/labels-conf-documented.sh [registry-root]
set -euo pipefail

die() { printf 'labels-conf-documented: %s\n' "$*" >&2; exit 1; }

[ "$#" -le 1 ] || die 'usage: bash test/labels-conf-documented.sh [registry-root]'
ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
CONF="$ROOT/.github/labels.conf"
DOC="$ROOT/CONTRIBUTING.md"

[ -f "$CONF" ] || die ".github/labels.conf is missing under $ROOT"
[ -f "$DOC" ] || die "CONTRIBUTING.md is missing under $ROOT"

mapfile -t panel_rows < <(sed -n 's/^panel=//p' "$CONF")
[ "${#panel_rows[@]}" -eq 1 ] \
  || die ".github/labels.conf must declare exactly one unqualified panel= row; CONTRIBUTING.md documents that default"

read -r -a configured_panel <<<"${panel_rows[0]}"
mapfile -t configured_panel < <(printf '%s\n' "${configured_panel[@]}" | LC_ALL=C sort -u)
[ "${#configured_panel[@]}" -gt 0 ] \
  || die '.github/labels.conf panel= declares no reviewers for CONTRIBUTING.md to document'
mapfile -t documented_panel < <(
  sed -n '/^2\. \*\*The review panel\*\*/,/^3\. \*\*Checks must be green\*\*/p' "$DOC" \
    | grep -Eo '[[:alnum:]-]+-bot-[[:alnum:]-]+' \
    | LC_ALL=C sort -u
)

mapfile -t configured_scopes < <(
  sed -n 's/^\(scope:[^|[:space:]]*\)|.*/\1/p' "$CONF" | LC_ALL=C sort -u
)
[ "${#configured_scopes[@]}" -gt 0 ] \
  || die '.github/labels.conf declares no scope:* rows for CONTRIBUTING.md to document'
mapfile -t documented_scopes < <(
  sed -n '/^## Labels — who sets what$/,/^## /p' "$DOC" \
    | grep -Eo 'scope:[[:alnum:]_-]+' \
    | LC_ALL=C sort -u
)

compare_set() {
  local label="$1" doc_name="$2" config_name="$3"
  local -n documented="$4" configured="$5"
  local documented_list configured_list

  documented_list="$(printf '%s\n' "${documented[@]}")"
  configured_list="$(printf '%s\n' "${configured[@]}")"
  if [ "$documented_list" != "$configured_list" ]; then
    die "$label differs: $doc_name names [${documented[*]}], but $config_name declares [${configured[*]}]; update both sets together"
  fi
}

compare_set 'default panel roster' 'CONTRIBUTING.md' '.github/labels.conf panel=' \
  documented_panel configured_panel
compare_set 'scope roster' 'CONTRIBUTING.md' '.github/labels.conf scope:* rows' \
  documented_scopes configured_scopes

printf 'labels-conf-documented: default panel held: %s\n' "${configured_panel[*]}"
printf 'labels-conf-documented: scopes held: %s\n' "${configured_scopes[*]}"
