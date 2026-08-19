# Release drills

A drill in this repository means: **every definition in the registry was
converged at least once, unattended, on real metal, at the ref being
released.** `drills/0.1.0.md` is written locally from the same real-hardware
session that produces rig's `drills/0.3.2.md` — one afternoon, two records —
because that run resolves machine roles *from this registry* and is therefore
this registry's evidence. **The gate still reads a file in this repo and
nothing else**, which is the doctrine that keeps a cross-repo lookup from
silently degrading to "pass".
