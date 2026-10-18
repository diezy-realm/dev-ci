# galleon-fleet CI

Trigger: the board (`board_switch.py review`), once per PR head; no timer. Gates: `gates.sh`.
Mirrors the lanes of `.github/workflows/ci.yml` in the repo (kept because `scripts/ci/*.test.sh` and
`tests/architecture/ci_runner_labels.rs` parse it); keep the two in step until those readers are retired.

| Gate | Tier | Blocks merge |
|---|---|---|
| Format (touched .rs files only; ~450 legacy files are not rustfmt-clean) | guard | yes |
| Repository Structure | guard | **no**: `.gitmodules` declares `docs/book/po` but the gitlink is absent on `testing` |
| Zerocode RPC Boundary | guard | yes |
| Principle (unwrap/expect, secrets, Gate D-2; D-1 and brand are warnings) | guard | yes |
| Lint (clippy, rustdoc, comment hygiene) | heavy | yes (baseline ratchet) |
| Check x2 (`-D warnings`) | heavy | yes (baseline ratchet) |
| Test (nextest) | heavy | **no**: advisory by Owner decision 2026-10-17 |
| Security (deny, audit, YAML, helper tests) | heavy | yes (baseline ratchet) |

Not run: Windows/macOS, Nix, Docker smoke, MSRV, 32-bit, benches, plugin backends, Landlock, postgres, galleon-web, Go engine.

## Baseline on `testing` (measured 2026-10-18, red before any PR)
- Lint: clippy `collapsible_if` in `crates/clawcrew-infra/src/cron_types.rs`.
- Check: dead-code errors under `-D warnings` (zerocode, clawcrew-channels util.rs, clawcrew-runtime).
- Test: does not compile (E0061 9 vs 10 args; unreadable `clawcrew-channels/src/discord/*` after the discord extraction).
- Security: `cargo deny` advisories (zip), bans (duplicate crates) and licenses.
- Repository Structure: see above.
