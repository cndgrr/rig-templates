#!/usr/bin/env bash
# agent-apt-extras.sh — the agent tenants' shared APT_EXTRAS base, held by a
# check rather than by prose.
#
# Every agent tenant here is a box crew may hire, and crew's box-side
# installer has hard prerequisites: it exits on a missing `gh` or `jq`, and a
# missing `crontab` is worse — the install completes, reports success, and
# hands the operator an apt command for a box that will never tick. Those are
# ordinary Debian packages, so they are ordinary APT_EXTRAS data, and the base
# below is what every agent tenant carries.
#
# Vendor additions layer ON TOP of the base: claude-box's `zsh` is a vendor
# addition and stays one. What the check refuses is a tenant DROPPING a base
# package, because four hand-maintained package lists drift in silence and the
# drift is invisible until a hire fails on the one box that lost `gh`.
#
# The boundary this also holds: a tenant gains crew's PACKAGES and never crew's
# ENGINE. `~/duty` is version-managed by crew and its integrity verdict is
# built on crew being that tree's sole writer, so a second writer makes every
# converged box read `modified`. Packages yes; the engine never.
#
# This check is the REGISTRY's, and deliberately not rig's. `rig template-lint`
# enforces rig's schema and must not learn one registry's conventions, so this
# runs beside it in this repo's CI and never inside it.
#
# usage: bash test/agent-apt-extras.sh [registry-root]
set -euo pipefail

ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# The documented base. README.md states it in prose; this array is what CI
# reads, so the two are changed together or the check is the one telling the
# truth.
BASE_PACKAGES=(cron gh jq)

# Installing crew's duty engine, expressed as the acts that would do it: a
# reference to the engine tree, crew's own installer, or the tick entrypoint.
# Matched against NON-COMMENT lines only, so a definition may document this
# boundary in a comment without tripping the check that enforces it.
ENGINE_PATTERNS=(
  '/duty'
  'DUTY_DIR'
  'engine-manifest'
  'tick\.sh'
  'crew[[:space:]]+(hire|upgrade|up|new)'
  'crew/shared/install'
)

die() { printf 'agent-apt-extras: %s\n' "$*" >&2; exit 1; }

[ -d "$ROOT" ] || die "no such registry root: $ROOT"

shopt -s nullglob

# An agent tenant is a *-box definition that installs an agent. AGENT is
# optional and defaults to yes, so staging-box's explicit AGENT="no" is what
# takes it out — the set is DERIVED and never a hand-kept list, which is the
# only way a fifth vendor tenant arrives already bound to the base.
tenants=()
for env_file in "$ROOT"/*-box/template.env; do
  role="$(basename "$(dirname "$env_file")")"
  agent="$(sed -n 's/^AGENT="\([^"]*\)"$/\1/p' "$env_file")"
  [ "${agent:-yes}" = no ] && continue
  tenants+=("$role")
done

[ ${#tenants[@]} -gt 0 ] \
  || die "no agent tenants found under $ROOT — an empty registry is a broken registry"

# --- The shared base --------------------------------------------------------
for role in "${tenants[@]}"; do
  env_file="$ROOT/$role/template.env"

  mapfile -t declarations < <(sed -n 's/^APT_EXTRAS="\([^"]*\)"$/\1/p' "$env_file")
  case ${#declarations[@]} in
    1) ;;
    0) die "$role/template.env declares no APT_EXTRAS; every agent tenant carries the shared base: ${BASE_PACKAGES[*]}" ;;
    *) die "$role/template.env declares APT_EXTRAS ${#declarations[@]} times; rig reads one value, so two lines are a silent loss" ;;
  esac

  read -r -a packages <<<"${declarations[0]}"
  for required in "${BASE_PACKAGES[@]}"; do
    found=no
    for package in "${packages[@]}"; do
      [ "$package" = "$required" ] && found=yes
    done
    [ "$found" = yes ] \
      || die "$role/template.env drops shared base package '$required' (base: ${BASE_PACKAGES[*]}); a tenant may ADD to the base, never subtract from it"
  done
done

# --- The ownership boundary -------------------------------------------------
# The withdrawn shape (@danmt on #21: "crew-server proceeds. crew-box is
# withdrawn"): the four tenants are widened in place, and crew membership never
# becomes a vendor role of its own.
for directory in "$ROOT"/crew-*-box/; do
  die "$(basename "${directory%/}") is a crew-flavoured vendor role; crew membership is a package list on the existing tenants, never a definition of its own"
done

# No definition in this registry installs crew's duty engine — every *-box and
# *-server hook, not only the agent tenants, because the boundary is the
# registry's and not one role family's.
for install_file in "$ROOT"/*/install.sh; do
  role="$(basename "$(dirname "$install_file")")"
  for pattern in "${ENGINE_PATTERNS[@]}"; do
    if grep -v '^[[:space:]]*#' "$install_file" | grep -Eq "$pattern"; then
      die "$role/install.sh looks like it installs crew's duty engine (matched '$pattern'); crew is ~/duty's sole writer, and a second writer makes every converged box read 'modified'"
    fi
  done
done

printf 'agent-apt-extras: base (%s) held across %s agent tenant(s): %s\n' \
  "${BASE_PACKAGES[*]}" "${#tenants[@]}" "${tenants[*]}"
printf 'agent-apt-extras: no crew-flavoured vendor role, and no definition installs crew'"'"'s duty engine\n'
