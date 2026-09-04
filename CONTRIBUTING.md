# Contributing

This repo is governed by
[heavy-duty/ceremony](https://github.com/heavy-duty/ceremony). **Agents:
read [`.ceremony/AGENTS.md`](.ceremony/AGENTS.md) first** — it routes you to
your role file (builder, reviewer, triage), vendored beside it as a
machine-managed mirror (never edited in place; it changes in
heavy-duty/ceremony, through its own flow). The review-round doctrine —
drafts, whole-round replies, verdicts, the handoff — lives there and in
[`.ceremony/LABELS.md`](.ceremony/LABELS.md); this file keeps only what is
genuinely rig-templates'.

## The PR loop, rig-templates specifics

1. **Fork and branch.** Contributors work from forks; upstream branches are
   for maintainers. Title the PR conventionally (`feat:`, `fix:`, `docs:`).
2. **The review panel** (`.github/labels.conf`'s `panel=` line):
   `claude-bot-andresmgsl`, `codex-bot-andresmgsl`,
   `kimi-bot-andresmgsl` — the required verdicts for a PR are the panel minus
   its author. The maintainer (`danmt`) takes the last word and merges.
   Requesting that panel is the PR author's own act here: no automation on
   this board requests panel members, so a ready head with nobody asked is
   waiting on its author rather than on a machine. The sweep caller
   ([`.github/workflows/labels-sweep.yml`](.github/workflows/labels-sweep.yml))
   writes the PR's `state:*` labels and may request the maintainer at the
   handoff — that is the only review request automation makes here. The
   request's own rules (a green check at the head, re-requesting by head, the
   roster minus the author) are
   [`.ceremony/BUILDER.md`](.ceremony/BUILDER.md)'s and are not repeated here.
3. **Checks must be green**: `rig template-lint` runs on every definition on
   every PR ([.github/workflows/ci.yml](.github/workflows/ci.yml)). rig owns
   the schema — a failing lint is fixed here, never worked around.
4. **Release changes write fragments** — behavior-changing PRs add one
   issue-keyed `changelog.d/<issue>.md` fragment with a grouped heading and
   terminal issue citation. Never edit `CHANGELOG.md` in an ordinary PR.

## Releases

A release is a `release`-labelled PR that changes `VERSION` from `X.Y.Z-dev`
to bare `X.Y.Z` and assembles every fragment into the stamped changelog
section. Merging that PR publishes the release; the workflow then re-arms
`main` at the next development version. A release drill means every definition
is linted, one definition is converged in a throwaway container, and a second
converge is compared mechanically, with the evidence and explicit limits
recorded in `drills/X.Y.Z.md` in this repo.

Rig still pins the commit a release tag names rather than trusting a mutable
tag. A merged PR here reaches mints only through a reviewed pin bump in rig,
or when a mint explicitly sets `RIG_TEMPLATES_REF`.

## Labels — who sets what

The taxonomy and state machine are
[`.ceremony/LABELS.md`](.ceremony/LABELS.md); this repo's `scope:*` rows
live in [`.github/labels.conf`](.github/labels.conf) (reconciled by the
labels caller) and their path map in
[`.github/labeler.yml`](.github/labeler.yml). `scope:roles` covers the role
definitions (the `*-box/` dirs); `scope:ci` covers the lint workflow and the
labels machinery itself. The set grows by ordinary PR when the repo does.

## The reviewer doctrine — install.sh is the line

**install.sh diffs here are the highest-trust review surface in the org;
hold them hardest.** Every role's `install.sh` executes as root inside any
mint that bumps rig's pin or sets `RIG_TEMPLATES_REF` — a subtle diff there
is a root payload with review as its only gate. Read every changed line of
an `install.sh` as an adversary would: what it fetches, what it writes
outside the tenant home, what runs before the drop to the tenant user.

That doctrine guards the security trade the README states in bold: a
main-tracked rig-templates repo means every merged PR here executes as root
inside every future mint. This is acceptable — and an improvement — only
because it narrows today's surface, the repo is small, single-purpose, and
ceremony-governed with a human merge as the gate and the review panel ahead
of it, and drills pin the SHA they proved. Since 2026-07-24 the default is
pinned (@danmt's ruling on rig#110): a merged PR here reaches mints only
through a reviewed pin bump in rig, or when a mint explicitly sets
`RIG_TEMPLATES_REF`. The review posture stands unchanged by the pin — the
override path and every future pin bump still ship these diffs as root.
