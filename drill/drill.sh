#!/usr/bin/env bash
set -euo pipefail

SELF="$(readlink -f "$0")"
ROOT="$(cd "$(dirname "$SELF")/.." && pwd)"

ROLE="${DRILL_ROLE:-staging-box}"
RECORD="${DRILL_RECORD:-}"
RIG_REF="${DRILL_RIG_REF:-main}"
IMAGE="${DRILL_IMAGE:-debian:13}"
RUN_ID="${DRILL_RUN_ID:-drill-$(date -u +%F)-$$}"
STRICT=0
YES=0

usage() {
  cat <<'EOF'
usage: bash drill/drill.sh [options]

Lint the complete registry, converge one role in a throwaway container, check
idempotence mechanically, and emit the drill record.

  --role <definition>    definition to converge (default: staging-box)
  --record <path>        record path; '-' writes stdout (default: drills/<VERSION>.md)
  --rig-ref <ref>        heavy-duty/rig ref supplying the mechanism (default: main)
  --image <image>        container image (default: debian:13)
  --run-id <id>          record join label (default: UTC date plus suffix)
  --strict               exit non-zero unless every leg passes
  --yes                   create and destroy the container without prompting
  -h, --help              show this help

The matching DRILL_ROLE, DRILL_RECORD, DRILL_RIG_REF, DRILL_IMAGE, and
DRILL_RUN_ID environment variables provide the same inputs. No credential is
read. Without --yes the command prints its plan and exits without running.
EOF
}

die() { printf 'drill: %s\n' "$*" >&2; exit 2; }
need_value() { [ $# -ge 2 ] || die "$1 needs a value"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --role) need_value "$@"; ROLE="$2"; shift 2 ;;
    --record) need_value "$@"; RECORD="$2"; shift 2 ;;
    --rig-ref) need_value "$@"; RIG_REF="$2"; shift 2 ;;
    --image) need_value "$@"; IMAGE="$2"; shift 2 ;;
    --run-id) need_value "$@"; RUN_ID="$2"; shift 2 ;;
    --strict) STRICT=1; shift ;;
    --yes) YES=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1 (see --help)" ;;
  esac
done

VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
if [ -z "$RECORD" ]; then
  case "$VERSION" in
    *-dev) die "VERSION is $VERSION; refusing to derive a release record path from a -dev tree. Pass --record explicitly." ;;
    '') die "VERSION is empty; pass --record explicitly" ;;
    *) RECORD="$ROOT/drills/$VERSION.md" ;;
  esac
fi

if [ "$YES" -ne 1 ]; then
  printf 'drill: would lint every definition, converge %s in %s, and write %s\n' "$ROLE" "$IMAGE" "$RECORD"
  printf 'drill: re-run with --yes to create and destroy the throwaway container\n'
  exit 0
fi

if [ -n "${RIG_TEMPLATES_DIR:-}" ] || [ -n "${RIG_TEMPLATES_REF:-}" ] || [ -n "${RIG_TEMPLATES_REPO:-}" ]; then
  die "RIG_TEMPLATES_DIR, RIG_TEMPLATES_REF, and RIG_TEMPLATES_REPO must be unset; the converge leg sets only RIG_TEMPLATES_DIR=/registry"
fi

shopt -s nullglob
definitions=("$ROOT"/*-box/ "$ROOT"/*-server/)
[ -d "$ROOT/workstation" ] && definitions+=("$ROOT/workstation/")
if [ ${#definitions[@]} -eq 0 ]; then
  printf 'drill: no role definitions found — an empty registry is a broken registry\n' >&2
  exit 1
fi
roles=()
for definition in "${definitions[@]}"; do roles+=("$(basename "$definition")"); done
if [ ! -f "$ROOT/$ROLE/template.env" ]; then
  die "unknown --role $ROLE; registry defines: ${roles[*]}"
fi
case "$ROLE" in
  *-box) ;;
  *) die "--role $ROLE is a credential-bearing machine definition; this drill converges tenant *-box definitions only" ;;
esac

user="$(sed -n 's/^USER="\([^"]*\)"$/\1/p' "$ROOT/$ROLE/template.env")"
agent="$(sed -n 's/^AGENT="\([^"]*\)"$/\1/p' "$ROOT/$ROLE/template.env")"; agent="${agent:-yes}"
harden="$(sed -n 's/^HARDEN_SSHD="\([^"]*\)"$/\1/p' "$ROOT/$ROLE/template.env")"; harden="${harden:-no}"
cli="$(sed -n 's/^CLI_NAME="\([^"]*\)"$/\1/p' "$ROOT/$ROLE/template.env")"
context="$(sed -n 's/^CONTEXT_PATH="\([^"]*\)"$/\1/p' "$ROOT/$ROLE/template.env")"

TMP="$(mktemp -d)"
CONTAINER="rig-templates-drill-${RUN_ID//[^A-Za-z0-9_.-]/-}-$$"
# shellcheck disable=SC2317  # invoked indirectly by the EXIT trap
cleanup() {
  docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
  rm -rf "$TMP"
}
trap cleanup EXIT

log() { printf 'drill: %s\n' "$*" >&2; }
now() { date +%s; }
results=(); durations=(); details=(); failures=0
record_leg() {
  results+=("$1")
  durations+=("$2")
  details+=("$3")
  [ "$1" = PASS ] || failures=$((failures + 1))
}

REPO_SHA="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || printf unknown)"
if [ -n "$(git -C "$ROOT" status --porcelain 2>/dev/null || true)" ]; then TREE_STATE=dirty; else TREE_STATE=clean; fi
RIG_SHA=unresolved
IMAGE_DIGEST=unresolved

start="$(now)"
log "fetching heavy-duty/rig@$RIG_REF"
if git clone --quiet --no-checkout --filter=blob:none https://github.com/heavy-duty/rig.git "$TMP/rig" \
  && git -C "$TMP/rig" fetch --quiet --depth=1 origin "$RIG_REF" \
  && git -C "$TMP/rig" checkout --quiet --detach FETCH_HEAD; then
  RIG_SHA="$(git -C "$TMP/rig" rev-parse HEAD)"
  lint_dirs=()
  for definition in "${definitions[@]}"; do lint_dirs+=("${definition%/}"); done
  set +e
  bash "$TMP/rig/bin/rig" template-lint "${lint_dirs[@]}" >"$TMP/lint.log" 2>&1
  lint_rc=$?
  set -e
  if [ "$lint_rc" -eq 0 ]; then
    record_leg PASS "$(( $(now) - start ))s" "${#roles[@]} definitions: ${roles[*]}"
  else
    record_leg FAIL "$(( $(now) - start ))s" "template-lint failed (see failures)"
    cp "$TMP/lint.log" "$TMP/lint.failure"
  fi
else
  record_leg FAIL "$(( $(now) - start ))s" "could not resolve heavy-duty/rig@$RIG_REF"
  : > "$TMP/lint.failure"
fi

container_reason=""
if ! command -v docker >/dev/null 2>&1; then
  container_reason="docker is unavailable"
elif ! docker info >/dev/null 2>&1; then
  container_reason="the docker daemon is unavailable"
elif [ "$RIG_SHA" = unresolved ]; then
  container_reason="the rig ref did not resolve"
fi

if [ -n "$container_reason" ]; then
  record_leg SKIPPED 0s "$container_reason"
  record_leg SKIPPED 0s "$container_reason"
else
  start="$(now)"
  log "pulling $IMAGE"
  if ! docker pull "$IMAGE" >"$TMP/pull.log" 2>&1; then
    container_reason="could not pull $IMAGE"
  else
    IMAGE_DIGEST="$(docker image inspect --format '{{index .RepoDigests 0}}' "$IMAGE" 2>/dev/null || printf unresolved)"
  fi

  if [ -z "$container_reason" ]; then
    log "starting privileged throwaway container $CONTAINER"
    if ! docker run -d --privileged --name "$CONTAINER" \
      --tmpfs /run --tmpfs /run/lock \
      -v "$ROOT:/registry:ro" -v "$TMP/rig:/rig-source:ro" \
      "$IMAGE" bash -lc \
      'apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y systemd-sysv dbus ca-certificates curl git sudo && exec /sbin/init' \
      >"$TMP/container.id" 2>"$TMP/container-start.log"; then
      container_reason="could not start $IMAGE"
    fi
  fi

  if [ -z "$container_reason" ]; then
    ready=0
    for _ in $(seq 1 120); do
      if docker exec "$CONTAINER" systemctl is-system-running >/dev/null 2>&1 \
        || docker exec "$CONTAINER" systemctl is-system-running 2>/dev/null | grep -q '^degraded$'; then
        ready=1; break
      fi
      sleep 1
    done
    [ "$ready" -eq 1 ] || container_reason="container init did not become ready"
  fi

  if [ -z "$container_reason" ]; then
    docker exec "$CONTAINER" useradd -m "$user" >"$TMP/seed.log" 2>&1 || true
    set +e
    docker exec -e RIG_INSTALL_SOURCE=/rig-source "$CONTAINER" bash /rig-source/install.sh >"$TMP/rig-install.log" 2>&1
    install_rc=$?
    set -e
    if [ "$install_rc" -ne 0 ]; then
      container_reason="rig installation failed"
    fi
  fi

  if [ -z "$container_reason" ]; then
    set +e
    docker exec -e RIG_TEMPLATES_DIR=/registry "$CONTAINER" bash -c '
      tree=$(dirname "$(dirname "$(readlink -f "$(command -v rig)")")")
      . "$tree/commands/lib/templates.sh"
      templates_resolve
      [ "$(readlink -f "$REGISTRY_DIR")" = /registry ]
    ' >"$TMP/source.log" 2>&1
    source_rc=$?
    set -e
    [ "$source_rc" -eq 0 ] || container_reason="rig did not resolve the mounted checkout at /registry"
  fi

  if [ -n "$container_reason" ]; then
    record_leg SKIPPED "$(( $(now) - start ))s" "$container_reason"
    record_leg SKIPPED 0s "$container_reason"
  else
    set +e
    docker exec -e RIG_TEMPLATES_DIR=/registry "$CONTAINER" rig bootstrap "$ROLE" >"$TMP/converge-1.log" 2>&1
    converge_rc=$?
    if [ "$converge_rc" -eq 0 ]; then
      docker exec "$CONTAINER" id "$user" >>"$TMP/converge-1.log" 2>&1 || converge_rc=1
      docker exec "$CONTAINER" docker info >>"$TMP/converge-1.log" 2>&1 || converge_rc=1
      if [ "$harden" = yes ]; then
        docker exec "$CONTAINER" bash -c "sshd -T | grep -qx 'passwordauthentication no'" >>"$TMP/converge-1.log" 2>&1 || converge_rc=1
      fi
      if [ "$agent" = yes ]; then
        docker exec "$CONTAINER" runuser -u "$user" -- "$cli" --version >>"$TMP/converge-1.log" 2>&1 || converge_rc=1
        docker exec "$CONTAINER" test -f "/home/$user/$context" >>"$TMP/converge-1.log" 2>&1 || converge_rc=1
      fi
    fi
    set -e
    if [ "$converge_rc" -eq 0 ]; then
      record_leg PASS "$(( $(now) - start ))s" "$ROLE converged from /registry; user, docker, and declared role assertions passed"
    else
      record_leg FAIL "$(( $(now) - start ))s" "$ROLE converge or its declared assertions failed"
      cp "$TMP/converge-1.log" "$TMP/converge.failure"
    fi

    if [ "$converge_rc" -ne 0 ]; then
      record_leg SKIPPED 0s "first converge failed"
    else
      # This is intentionally single-quoted: the variables expand inside the
      # container's bash, not in this host-side script.
      # shellcheck disable=SC2016
      capture='user=$1; context=$2; { dpkg-query -W -f="${Package} ${Version}\n" | sort; sshd -T 2>/dev/null | sort || true; getent passwd "$user"; id "$user"; systemctl is-enabled cron 2>/dev/null || true; systemctl is-active cron 2>/dev/null || true; crontab -u "$user" -l 2>/dev/null || true; { find /etc/ssh/sshd_config.d -maxdepth 1 -type f 2>/dev/null; find /home/"$user" -maxdepth 1 -type f \( -name ".*rc" -o -name ".profile" -o -name ".zshenv" -o -name ".tmux.conf" \) 2>/dev/null; printf "%s\n" /etc/rig/role /etc/rig/manifest; [ -n "$context" ] && printf "/home/%s/%s\n" "$user" "$context"; } | sort -u | while read -r path; do [ -f "$path" ] && sha256sum "$path"; done; }'
      docker exec "$CONTAINER" bash -c "$capture" snapshot "$user" "$context" >"$TMP/snapshot-1"
      start="$(now)"
      set +e
      docker exec -e RIG_TEMPLATES_DIR=/registry "$CONTAINER" rig bootstrap "$ROLE" >"$TMP/converge-2.log" 2>&1
      second_rc=$?
      docker exec "$CONTAINER" bash -c "$capture" snapshot "$user" "$context" >"$TMP/snapshot-2"
      diff -u "$TMP/snapshot-1" "$TMP/snapshot-2" >"$TMP/snapshot.diff"
      diff_rc=$?
      set -e
      if [ "$second_rc" -eq 0 ] && [ "$diff_rc" -eq 0 ]; then
        record_leg PASS "$(( $(now) - start ))s" "second converge produced a byte-identical mechanical snapshot"
      else
        record_leg FAIL "$(( $(now) - start ))s" "second converge failed or snapshot diff was non-empty"
      fi
    fi
  fi
fi

disclosure="This agentless run did not exercise agent-tenant install.sh (the registry's highest-trust root surface), creds.md, the rendered agent-context file, NEEDS_NODE, or the duty-engine cron converge. Machine roles requiring a tailnet credential are excluded by construction."
if [ "$agent" = yes ]; then
  disclosure="This optional $ROLE run exercised its install.sh, creds.md, rendered agent-context file, and NEEDS_NODE behavior. It did not exercise the other agent tenants, duty-engine cron converge, or credential-bearing machine roles."
fi

emit_record() {
  local output="$1" index failure_file
  # Backticks below are Markdown delimiters, not command substitutions.
  # shellcheck disable=SC2016
  {
    printf '# Registry drill — %s — %s\n\n' "$VERSION" "$(date -u +%F)"
    printf -- '- Run ID: `%s`\n' "$RUN_ID"
    printf -- '- Registry: `%s` (%s tree)\n' "$REPO_SHA" "$TREE_STATE"
    printf -- '- Rig: `%s` resolved to `%s`\n' "$RIG_REF" "$RIG_SHA"
    printf -- '- Container image: `%s` (`%s`)\n' "$IMAGE" "$IMAGE_DIGEST"
    printf -- '- Definition converged: `%s`\n\n' "$ROLE"
    printf '| Leg | Result | Duration | Detail |\n| --- | --- | --- | --- |\n'
    for index in 0 1 2; do
      printf '| %s | %s | %s | %s |\n' "$((index + 1))" "${results[$index]}" "${durations[$index]}" "${details[$index]//|/\\|}"
    done
    printf '\n## Not exercised\n\n%s\n' "$disclosure"
    printf '\n## Failures and skips\n\n'
    if [ "$failures" -eq 0 ]; then
      printf 'None. Every leg passed.\n'
    else
      for index in 0 1 2; do
        [ "${results[$index]}" = PASS ] || printf -- '- Leg %s — %s: %s\n' "$((index + 1))" "${results[$index]}" "${details[$index]}"
      done
      for failure_file in "$TMP"/*.failure; do
        [ -f "$failure_file" ] || continue
        printf '\n```text\n'
        tail -n 80 "$failure_file"
        printf '```\n'
      done
      if [ -s "$TMP/snapshot.diff" ]; then
        printf '\nSnapshot diff (first 120 lines):\n\n```diff\n'
        sed -n '1,120p' "$TMP/snapshot.diff"
        printf '```\n'
      fi
    fi
  } > "$output"
}

if [ "$RECORD" = - ]; then
  emit_record /dev/stdout
else
  mkdir -p "$(dirname "$RECORD")"
  emit_record "$RECORD"
  log "record written to $RECORD"
fi

if [ "$STRICT" -eq 1 ] && [ "$failures" -ne 0 ]; then exit 1; fi
exit 0
