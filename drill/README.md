# The registry drill

`drill/drill.sh` proves the release registry is readable and convergent. It
lints every definition, converges one definition in a privileged throwaway
Debian 13 container, repeats the converge, and compares mechanical snapshots.
It needs Docker and outbound network access, but no credential or secret.

Run the default drill from the repository root:

```sh
bash drill/drill.sh --record - --yes
```

The three timed legs of a default run are:

1. one `rig template-lint` invocation over every `*-box`, `*-server`, and
   `workstation` definition;
2. `staging-box` convergence from the read-only checkout mounted at
   `/registry`, after rig's source resolver confirms that exact path;
3. a second identical converge followed by a byte-for-byte comparison of
   packages, effective sshd configuration, the tenant account, and hashes of
   the files convergence owns.

Docker, privilege, or network being unavailable does not erase the run. The
lint leg still runs, the container legs are recorded as `SKIPPED` with their
reason, and the complete record exits zero. Add `--strict` when every leg must
be `PASS` for the caller to succeed.

A container whose init never becomes ready is likewise unavailable and is
recorded as `SKIPPED`. Once the container is ready, a rig installation failure
or a mounted-checkout resolution mismatch is an instrument finding and is
recorded as `FAIL`, while leg 3 is `SKIPPED` because no first converge ran.

An agent tenant can be exercised explicitly:

```sh
bash drill/drill.sh --role claude-box --record - --yes
```

That additionally checks the CLI as the tenant user and the rendered agent
context. It costs a vendor install and is intentionally not the release
default. `bash drill/drill.sh --help` documents all flags and environment
equivalents. Without `--yes`, the script only prints its plan.

## The crew-member leg

`--crew-member` adds a fourth leg to an agent-tenant run, and refuses an
agentless `--role`:

```sh
bash drill/drill.sh --role codex-box --crew-member --record - --yes --strict
```

Every agent tenant here exists to run crew's cron-driven duty engine, so the
leg asks the only question that matters: does a box converged from this
registry survive `crew hire` with no manual apt step? It resolves `gh`, `jq`,
`sha256sum` and `crontab` as the tenant, asserts `cron.service` is active, and
runs crew's own box-side installer — unprivileged and credential-free —
to completion.

**Cron armed is not cron installed.** The installer exits `0` after warning
that no cron daemon is running, which is exactly the box that reports success
and never ticks, so the exit code alone is not the evidence. The leg reads
what the installer *said* about the arming — `crontab armed` and `cron daemon
running`, and never `cron is not armed` — and confirms the member crontab
carries the tick entry.

The leg runs **after** the idempotence leg: arming a crontab is a mutation and
must not land between the two snapshots it would then appear in. It pins the
crew ref it exercises (`--crew-ref`, default `0.1.2`) the way the drill pins
its rig ref, and the record names the SHA that ref resolved to. The record
also states the leg's limit: rig's agent-tenant toolbelt installs `gh`, `jq`
and `cron` itself (rig#162), so the leg proves the converged box satisfies
crew — never which layer supplied each package.
