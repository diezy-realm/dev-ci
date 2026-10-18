# dev-ci

Local CI for GitHub PRs, shared by all repos. No GitHub Actions, no tunnel, no webhook: the board
bridge fires CI per PR, gates run in throwaway containers, and results report back as commit statuses.
Local git only (never pushed), like `~/Apps/board`.

**Trigger model (event-driven, not timer):** `board_agy_bridge.py` calls `ci-poller <repo> --pr N` in
the background the moment a task is parked in `review` (i.e. agy just pushed/updated its PR). One push =
one CI run. `flock` inside `ci-poller` serializes overlapping runs, so at most one build runs at a time
(`CPUS=3`, leaving a core for agy/system on this 4-core host). The `systemd/dev-ci-poller.{service,timer}`
files are kept **only as an inactive backup** (NOT installed/enabled) in case the event trigger is ever
unavailable; re-arm with `systemctl --user enable --now` from a copy if needed.

| Path | Scope | What |
|---|---|---|
| `bin/ci-poller` | general | `ci-poller <repo> [--dry-run] [--pr N] [--force]`: poll, run gates, post statuses, auto-merge |
| `image/` | general | Dockerfile of the CI image (`dev-ci:local`: Rust via rustup, protoc, mold, nextest, deny, audit, sccache) |
| `systemd/` | general | `dev-ci-poller.{service,timer}` (symlinked into `~/.config/systemd/user`) |
| `repos/<repo>/ci.env` | per repo | repo slug, target branches, CPU/RAM, auto-merge policy |
| `repos/<repo>/gates.sh` | per repo | the gate list (`gates.sh list`) and what each gate runs (`gates.sh run <name>`) |
| `logs/<repo>/pr<N>-<sha8>/` | state | one log per gate + `summary.json`; newest 40 kept |
| `work/<repo>.git` | state | bare mirror of the repo (read-only inside containers) |
| `state/baseline/<repo>/<sha>.json` | cache | which gates are already red at a merge-base |

## How a poll works
1. Open PRs into `BASES` (same-repo heads, not drafts) whose head SHA has no final `local/Required Gate` status.
2. Per PR: clone the SHA into a per-PR docker volume (network on: clone, toolchain, `cargo fetch --locked`),
   then run each gate in its own container, `--network none` unless the gate says `full`.
3. One commit status per gate (`local/<gate>`) plus `local/Required Gate`. A cheap guard gate that is red skips the heavy gates.
4. **Baseline ratchet:** a required gate that fails is re-run on the PR's merge-base. If it is red there too, the PR is
   not blamed (status success, "red on <base> too"). Fix a baseline and the protection comes back automatically.
   Limitation: a gate that is already red on the base cannot catch a new regression of the same gate.
5. PRs into `AUTOMERGE_BASES` whose head matches `AUTOMERGE_HEAD_REGEX` are squash-merged when green (head SHA pinned).
   `main` is never auto-merged. **Currently OFF** (`AUTOMERGE_BASES=` empty) until PR #47/#48 are cleaned of the
   Codesmith CI commits; a green PR therefore stays in `review` for a manual merge. Set `AUTOMERGE_BASES=testing` to enable.

GitHub commit statuses are the only state for "was this SHA tested"; the board reads them (`board_switch.py review`).

## Operate
```
~/Apps/dev-ci/bin/ci-poller galleon-fleet --dry-run       # what would run
~/Apps/dev-ci/bin/ci-poller galleon-fleet --pr 55 --force # force a re-run of one PR
```
CI is normally fired by the board bridge per PR (see Trigger model) — you rarely invoke it by hand.
Rebuild the image after editing `image/`: `docker build -t dev-ci:local ~/Apps/dev-ci/image`.
Caches live in docker volumes named `<VOL_PREFIX>_{cargo-home,rustup-home,ci-target,sccache}` (VOL_PREFIX=`dev-ci`); `ci-target` is wiped when it passes `CI_TARGET_MAX_GB`.

## Add a repo
1. `mkdir repos/<repo>`; copy `ci.env` and `gates.sh` from `repos/galleon-fleet` and edit.
2. `systemd/dev-ci-poller.service` is galleon-fleet specific (`ExecStart ... ci-poller galleon-fleet`); copy it to a new unit per repo.

## Security model
- Containers: no host home, ssh keys, Docker socket or published ports; all caps dropped; no-new-privileges; CPU, RAM, pid limits.
- Gates run with no network, except the fetch/prepare step and gates marked `full` (advisory DBs). The host never executes
  anything from a PR checkout: clone, build and test all happen inside containers, and the mirror is mounted read-only.
- Only same-repo PRs get CI (fork PRs are ignored). Gate scripts come from the PR tree, so a PR can edit the gate it is judged by.
- Residual risk: a `full` container shares the default bridge, so it can reach the LAN and host services bound to 0.0.0.0.
