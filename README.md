# dev-ci

Local CI infrastructure shared by all repos. Local git only (never pushed), like `~/Apps/board`.

| Path | Scope | What |
|---|---|---|
| `runner/` | general | Docker image (Rust, Node, Python, sccache, nextest, deny, audit, Actions runner) and compose template |
| `bin/ci-runner` | general | `ci-runner <repo> up|down|ps|logs|token|restart` |
| `repos/<repo>/runner.env` | per repo | repo URL, label prefix, CPU/RAM limits, compose project name |
| `repos/<repo>/README.md` | per repo | which gates run, known baseline failures, repo-specific notes |

Workflows themselves stay in each repo's `.github/workflows/` (they must, GitHub reads them there).
A repo only needs `runs-on: [self-hosted, linux, <prefix>-heavy|<prefix>-light]`.

## Add a repo
1. `mkdir repos/<repo>` and copy `repos/galleon-fleet/runner.env`; change `PROJECT`, `REPO_*`, `RUNNER_PREFIX`.
2. `RUNNER_TOKEN=$(bin/ci-runner <repo> token) bin/ci-runner <repo> up` (token is only needed on the first start).

## Security model
- Containers: no host home, ssh keys, Docker socket or published ports; all caps dropped; no-new-privileges; CPU, RAM and pid limits.
- Outbound HTTPS only (the runner long-polls GitHub). Nothing listens on the host.
- Residual risk: containers share the default Docker bridge, so they can reach other hosts on the LAN and any host service bound to 0.0.0.0. A runner executes PR code, so keep repos private and fork-PR workflows off.
- GitHub side (galleon-fleet): fork PR workflows off, workflow token read-only, allowed actions limited to GitHub-owned plus an explicit list.
