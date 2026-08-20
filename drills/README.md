# Release drills

A drill in this repository means, at the ref being released: `rig
template-lint` green on **every** definition in the registry, and **at least
one** definition converged end-to-end in a throwaway container and
re-converged to a clean no-op. The record names which definition was converged
and states, in its own words, what the drill did **not** exercise.

`drill/drill.sh` emits the record; it is never reconstructed by hand. Each
record names the version and UTC date, run ID, registry commit and tree state,
rig ref and resolved SHA, image digest, definition converged, timed PASS / FAIL
/ SKIPPED legs, every failure, and the surfaces not exercised. A waiver is the
one exception: a human writes the version file with the reason, making the
waiver a reviewable commit rather than an instrument output.

Records are `drills/<version>.md`, with the name taken from `VERSION` exactly.
When `VERSION` ends in `-dev`, the script refuses to derive a path and names
`--record`; it neither writes a `-dev` record the release gate ignores nor
strips the suffix and claims to evidence a release tree.

This meaning replaces the real-metal, every-definition ruling on 2026-08-20.
The release gate still reads a non-empty version file in this repository and
nothing else.
