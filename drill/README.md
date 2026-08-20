# The registry drill

`drill/drill.sh` proves the release registry is readable and convergent. It
lints every definition, converges one definition in a privileged throwaway
Debian 13 container, repeats the converge, and compares mechanical snapshots.
It needs Docker and outbound network access, but no credential or secret.

Run the default drill from the repository root:

```sh
bash drill/drill.sh --record - --yes
```

The three timed legs are:

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
