# rig-templates — the tenant-role registry

The role definitions [rig](https://github.com/heavy-duty/rig) converges onto
box-minted guests (rig#110). rig keeps the **mechanism** — convergence
discipline, the marker/manifest guards, docker, the context-file renderer
with the box#80 boilerplate; this repo keeps the **registry**: the per-role
data that used to live as case arms in rig's tree. The split exists because
the two move at different cadences — adding an agent tenant is a data PR
here, never a mechanism edit there (rig#109 is the evidence: adding kimi,
pure data, meant editing six files in a mechanism repo).

This repo deliberately has **no release ceremony**: it is pinned from the
consumer side. rig's tree records the ref it converges by default
(`RIG_TEMPLATES_PIN` in `commands/lib/templates.sh`, the `BOX_RELEASE`
discipline), bumped by ordinary reviewed rig PR — so a newer rig matches
newer templates by default, and a mint overrides per run:

    RIG_TEMPLATES_DIR=<dir>    a local folder, no fetch (tests; try-before-push)
    RIG_TEMPLATES_REF=<ref>    any ref here (or in RIG_TEMPLATES_REPO), fetched
                               as an unauthenticated tarball at bootstrap time
    (neither)                  rig's in-tree pin

## Layout — one directory per role, flat, self-namespaced by suffix

The name carries the family (rig#76): `-box` for box tenants and `-server`
for machine roles. `workstation` is the one intentional suffix-less machine
role because it names the machine itself rather than a server purpose.

    claude-box/
    ├── template.env   KEY="value" data, parsed by rig against an allowlist,
    │                  NEVER sourced: USER, CONTEXT_PATH, CLI_NAME, CLI_SRC,
    │                  PATH_LINE, NEEDS_NODE, APT_EXTRAS, AGENT, HARDEN_SSHD
    ├── install.sh     the CLI install — the one deliberately executable part,
    │                  run by the mechanism AS ROOT with TENANT_USER /
    │                  TENANT_HOME / TENANT_GROUP / ROLE exported; it drops to
    │                  the tenant user (runuser -l) where the vendor's layout
    │                  demands it
    └── creds.md       the per-vendor creds-free paragraph rig's context
                       renderer splices into the agent-context file

`template.env` grammar: blank lines, `#` comments, and `KEY="value"` —
nothing else. The value is everything between the first `="` and the line's
final `"`, so a `PATH_LINE` may carry inner quotes verbatim. It is data:
rig parses it against the allowlist and refuses anything else by key —
it is never sourced, so a definition cannot execute shell through its data
file. `CLI_SRC` may be `~/`-prefixed; rig expands that to the tenant home by
string substitution. Omit `CLI_SRC` when the install lands on the system
PATH already (codex: an npm global's path is the prefix's fact) — rig then
finds the CLI via `command -v`.

Tenant definitions default to `AGENT="yes"` and `HARDEN_SSHD="no"`, so
definitions written before those keys are unchanged. `AGENT="no"` keeps
`USER` required, refuses agent-only keys and `creds.md`, and makes
`install.sh` optional. `HARDEN_SSHD="yes"` invokes rig's shared sshd
hardening independently of whether an agent is installed.

Machine-role directories are traits-only: their `template.env` allowlist is
`ROOT_DOOR`, `HOST`, and `JOIN`. They carry no `creds.md`; an `install.sh` is
optional in the schema but absent from the built-in machine definitions.

## CI — rig lints every definition on every PR

rig defines what a valid template is (`rig template-lint`, shipped beside
the mint-time parser that enforces the same schema); this repo's CI runs it
on every definition on every PR, so a broken definition is refused before it
can ever reach a mint. The two gates are not redundant: CI protects the
registry, rig's bootstrap-time parse protects a mint served through
`RIG_TEMPLATES_REPO`/`_DIR` that CI never saw.

## The security trade — in bold, not a footnote

**A main-tracked rig-templates repo means every merged PR there executes as
root inside every future mint.** This is acceptable — and an improvement —
only because of three facts together: (1) it *narrows* today's surface,
where all of rig is main-tracked-as-root; (2) the repo is small,
single-purpose, and ceremony-governed with a **human merge** as the gate and
the review panel ahead of it; (3) drills pin the SHA they proved. If any of
those three weakens, the default flips to a pinned `RIG_TEMPLATES_REF`.
install.sh diffs in that repo are the highest-trust review surface in the
org — the reviewer doctrine should say so.

*2026-07-24: the flip that paragraph reserves was taken, before the
migration and by the decider* (rig#110): the default **is** pinned — a
merged PR here reaches mints only through a reviewed pin bump in rig, or
when a mint explicitly sets `RIG_TEMPLATES_REF`. The review posture stands
unchanged: **install.sh diffs here remain the highest-trust review surface**,
because the override path and every future pin bump still ship them as root.
