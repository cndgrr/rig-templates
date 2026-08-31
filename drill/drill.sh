#!/usr/bin/env bash
set -euo pipefail

SELF="$(readlink -f "$0")"
ROOT="$(cd "$(dirname "$SELF")/.." && pwd)"

ROLE="${DRILL_ROLE:-staging-box}"
RECORD="${DRILL_RECORD:-}"
RIG_REF="${DRILL_RIG_REF:-main}"
CREW_REF="${DRILL_CREW_REF:-0.1.2}"
IMAGE="${DRILL_IMAGE:-debian:13}"
RUN_ID="${DRILL_RUN_ID:-drill-$(date -u +%F)-$$}"
STRICT=0
YES=0
CREW_MEMBER="${DRILL_CREW_MEMBER:-0}"

usage() {
  cat <<'EOF'
usage: bash drill/drill.sh [options]

Lint the complete registry, converge one role in a throwaway container, check
idempotence mechanically, and emit the drill record.

  --role <definition>    definition to converge (default: staging-box)
  --record <path>        record path; '-' writes stdout (default: drills/<VERSION>.md)
  --rig-ref <ref>        heavy-duty/rig ref supplying the mechanism (default: main)
  --crew-ref <ref>       heavy-duty/crew ref supplying the member engine (default: 0.1.2)
  --crew-member          add the crew-member leg: crew's box-side installer, run
                         credential-free on the converged tenant, and cron armed
  --image <image>        container image (default: debian:13)
  --run-id <id>          record join label (default: UTC date plus suffix)
  --strict               exit non-zero unless every leg passes
  --yes                  create and destroy the container without prompting
  -h, --help             show this help

The matching DRILL_ROLE, DRILL_RECORD, DRILL_RIG_REF, DRILL_CREW_REF,
DRILL_CREW_MEMBER, DRILL_IMAGE, and DRILL_RUN_ID environment variables provide
the same inputs. No credential is read, by the drill or by the crew-member leg.
Without --yes the command prints its plan and exits without running.
EOF
}

die() { printf 'drill: %s\n' "$*" >&2; exit 2; }
need_value() { [ $# -ge 2 ] || die "$1 needs a value"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --role) need_value "$@"; ROLE="$2"; shift 2 ;;
    --record) need_value "$@"; RECORD="$2"; shift 2 ;;
    --rig-ref) need_value "$@"; RIG_REF="$2"; shift 2 ;;
    --crew-ref) need_value "$@"; CREW_REF="$2"; shift 2 ;;
    --crew-member) CREW_MEMBER=1; shift ;;
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
  printf 'drill: would lint every definition, converge %s in %s, and write %s' "$ROLE" "$IMAGE" "$RECORD"
  if [ "$CREW_MEMBER" -eq 1 ]; then
    printf ', then exercise crew@%s'"'"'s box-side installer on the converged tenant' "$CREW_REF"
  fi
  printf '\n'
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
if [ "$CREW_MEMBER" -eq 1 ] && [ "$agent" != yes ]; then
  die "--crew-member needs an agent tenant; --role $ROLE declares AGENT=\"$agent\" and runs no duty engine"
fi

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
CREW_SHA=not-exercised
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

# The leg pins the crew ref it exercises, as the drill pins its rig ref, and
# records the SHA that ref resolved to: a record naming a moving tag evidences
# nothing a reader can go back to.
if [ "$CREW_MEMBER" -eq 1 ]; then
  log "fetching heavy-duty/crew@$CREW_REF"
  if git clone --quiet --no-checkout --filter=blob:none https://github.com/heavy-duty/crew.git "$TMP/crew" \
    && git -C "$TMP/crew" fetch --quiet --depth=1 origin "$CREW_REF" \
    && git -C "$TMP/crew" checkout --quiet --detach FETCH_HEAD; then
    CREW_SHA="$(git -C "$TMP/crew" rev-parse HEAD)"
  else
    CREW_SHA=unresolved
  fi
fi

container_reason=""
container_result=SKIPPED
if ! command -v docker >/dev/null 2>&1; then
  container_reason="docker is unavailable"
elif ! docker info >/dev/null 2>&1; then
  container_reason="the docker daemon is unavailable"
elif [ "$RIG_SHA" = unresolved ]; then
  container_reason="the rig ref did not resolve"
elif [ "$CREW_MEMBER" -eq 1 ] && [ "$CREW_SHA" = unresolved ]; then
  container_reason="the crew ref did not resolve"
fi

if [ -n "$container_reason" ]; then
  record_leg SKIPPED 0s "$container_reason"
  record_leg SKIPPED 0s "$container_reason"
  if [ "$CREW_MEMBER" -eq 1 ]; then record_leg SKIPPED 0s "$container_reason"; fi
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
    crew_mount=()
    if [ "$CREW_MEMBER" -eq 1 ]; then crew_mount=(-v "$TMP/crew:/crew-source:ro"); fi
    if ! docker run -d --privileged --name "$CONTAINER" \
      --tmpfs /run --tmpfs /run/lock \
      -v "$ROOT:/registry:ro" -v "$TMP/rig:/rig-source:ro" \
      "${crew_mount[@]}" \
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
      container_result=FAIL
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
    if [ "$source_rc" -ne 0 ]; then
      container_reason="rig did not resolve the mounted checkout at /registry"
      container_result=FAIL
    fi
  fi

  if [ -n "$container_reason" ]; then
    record_leg "$container_result" "$(( $(now) - start ))s" "$container_reason"
    record_leg SKIPPED 0s "$container_reason"
    if [ "$CREW_MEMBER" -eq 1 ]; then record_leg SKIPPED 0s "$container_reason"; fi
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
      capture='user=$1; context=$2; { dpkg-query -W -f="${Package} ${Version}\n" | sort; sshd -T 2>/dev/null | sort || true; getent passwd "$user"; id "$user"; systemctl is-enabled cron 2>/dev/null || true; systemctl is-active cron 2>/dev/null || true; crontab -u "$user" -l 2>/dev/null || true; { find /etc/ssh/sshd_config.d -maxdepth 1 -type f 2>/dev/null; find /home/"$user" -maxdepth 1 -type f \( -name ".*rc" -o -name ".profile" -o -name ".zshenv" -o -name ".tmux.conf" \) 2>/dev/null; printf "%s\n" /etc/rig/role /etc/rig/manifest; [ -n "$context" ] && printf "/home/%s/%s\n" "$user" "$context"; } | sort -u | while read -r path; do if [ -f "$path" ]; then sha256sum "$path"; fi; done; }'
      start="$(now)"
      set +e
      docker exec "$CONTAINER" bash -c "$capture" snapshot "$user" "$context" >"$TMP/snapshot-1" 2>"$TMP/snapshot-1.log"
      snapshot_1_rc=$?
      second_rc=1
      snapshot_2_rc=1
      diff_rc=1
      if [ "$snapshot_1_rc" -eq 0 ]; then
        docker exec -e RIG_TEMPLATES_DIR=/registry "$CONTAINER" rig bootstrap "$ROLE" >"$TMP/converge-2.log" 2>&1
        second_rc=$?
        docker exec "$CONTAINER" bash -c "$capture" snapshot "$user" "$context" >"$TMP/snapshot-2" 2>"$TMP/snapshot-2.log"
        snapshot_2_rc=$?
        if [ "$snapshot_2_rc" -eq 0 ]; then
          diff -u "$TMP/snapshot-1" "$TMP/snapshot-2" >"$TMP/snapshot.diff"
          diff_rc=$?
        fi
      fi
      set -e
      if [ "$snapshot_1_rc" -eq 0 ] && [ "$second_rc" -eq 0 ] && [ "$snapshot_2_rc" -eq 0 ] && [ "$diff_rc" -eq 0 ]; then
        record_leg PASS "$(( $(now) - start ))s" "second converge produced a byte-identical mechanical snapshot"
      else
        record_leg FAIL "$(( $(now) - start ))s" "snapshot capture, second converge, or snapshot comparison failed"
      fi
    fi

    if [ "$CREW_MEMBER" -eq 1 ]; then
      if [ "$converge_rc" -ne 0 ]; then
        record_leg SKIPPED 0s "first converge failed"
      else
        # Ordered after the idempotence leg deliberately: arming a crontab is a
        # mutation, and it must not land between the two snapshots it would
        # then show up in.
        start="$(now)"
        crew_rc=0
        set +e
        # The four prerequisites, resolved the way crew's installer resolves
        # them — as the tenant, on the tenant's own PATH.
        # shellcheck disable=SC2016  # $command is the container shell's loop variable
        docker exec "$CONTAINER" runuser -l "$user" -c \
          'for command in gh jq sha256sum crontab; do command -v "$command" || exit 1; done' \
          >"$TMP/crew.log" 2>&1 || crew_rc=1
        # ARMED is a running daemon, never an installed package. A box that
        # reports success and never ticks is the failure this leg exists for,
        # so command -v crontab alone is not allowed to satisfy it.
        docker exec "$CONTAINER" systemctl is-active cron >>"$TMP/crew.log" 2>&1 || crew_rc=1
        # crew's own box-side installer, unprivileged and credential-free.
        docker exec "$CONTAINER" runuser -l "$user" -c \
          "bash /crew-source/shared/install.sh --agent $user --role builder --arm-cron" \
          >>"$TMP/crew.log" 2>&1 || crew_rc=1
        set -e
        # Its exit code is not the evidence on its own: the installer exits 0
        # after WARNING that no cron daemon is running, which is precisely the
        # silent box. Read what it said about the arming.
        grep -qF 'crontab armed' "$TMP/crew.log" || crew_rc=1
        grep -qF 'cron daemon running' "$TMP/crew.log" || crew_rc=1
        if grep -qF 'cron is not armed' "$TMP/crew.log"; then crew_rc=1; fi
        docker exec "$CONTAINER" crontab -u "$user" -l >>"$TMP/crew.log" 2>&1 || crew_rc=1
        docker exec "$CONTAINER" crontab -u "$user" -l 2>/dev/null \
          | grep -qF "/home/$user/duty/bin/tick.sh" || crew_rc=1
        if [ "$crew_rc" -eq 0 ]; then
          record_leg PASS "$(( $(now) - start ))s" "crew@$CREW_REF installed on $ROLE: gh, jq, sha256sum and crontab all resolved as $user, cron.service was active, and the member crontab carries the tick entry"
        else
          record_leg FAIL "$(( $(now) - start ))s" "crew@$CREW_REF prerequisites, box-side install, or crontab arming failed on $ROLE"
          cp "$TMP/crew.log" "$TMP/crew.failure"
        fi
      fi
    fi
  fi
fi

definition_converged="$ROLE"
disclosure="This agentless run did not exercise agent-tenant install.sh (the registry's highest-trust root surface), creds.md, the rendered agent-context file, NEEDS_NODE, or the duty-engine cron converge. Machine roles requiring a tailnet credential are excluded by construction."
if [ "${results[1]}" != PASS ]; then
  definition_converged="none (leg 2 ${results[1]})"
  disclosure="No definition was converged, so this run exercised no tenant install.sh, creds.md, rendered agent-context file, NEEDS_NODE behavior, or duty-engine cron converge. Machine roles requiring a tailnet credential are excluded by construction."
elif [ "$agent" = yes ]; then
  disclosure="This optional $ROLE run exercised its install.sh, creds.md, rendered agent-context file, and NEEDS_NODE behavior. It did not exercise the other agent tenants, duty-engine cron converge, or credential-bearing machine roles."
fi
if [ "$CREW_MEMBER" -eq 1 ] && [ "${results[3]:-}" = PASS ]; then
  disclosure="This $ROLE run exercised its install.sh, creds.md, rendered agent-context file, NEEDS_NODE behavior, and crew@$CREW_REF's credential-free box-side installer through an armed crontab on a running cron daemon. It did not exercise the other agent tenants or credential-bearing machine roles. It does not attribute the four prerequisites to this registry's APT_EXTRAS: rig's agent-tenant toolbelt installs gh, jq and cron itself (rig#162), so the leg proves the converged box satisfies crew, never which layer supplied each package."
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
    if [ "$CREW_MEMBER" -eq 1 ]; then
      printf -- '- Crew member engine: `%s` resolved to `%s`\n' "$CREW_REF" "$CREW_SHA"
    fi
    printf -- '- Container image: `%s` (`%s`)\n' "$IMAGE" "$IMAGE_DIGEST"
    printf -- '- Definition converged: `%s`\n\n' "$definition_converged"
    printf '| Leg | Result | Duration | Detail |\n| --- | --- | --- | --- |\n'
    for index in "${!results[@]}"; do
      printf '| %s | %s | %s | %s |\n' "$((index + 1))" "${results[$index]}" "${durations[$index]}" "${details[$index]//|/\\|}"
    done
    printf '\n## Not exercised\n\n%s\n' "$disclosure"
    printf '\n## Failures and skips\n\n'
    if [ "$failures" -eq 0 ]; then
      printf 'None. Every leg passed.\n'
    else
      for index in "${!results[@]}"; do
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
