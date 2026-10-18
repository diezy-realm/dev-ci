# galleon-fleet CI

Runners: `galleon-heavy` (compile/test, shared target dir capped at 60G, sccache 20G) and `galleon-light` (guards, labelers, auto-merge, Principle gates).

## Gate (Quality Gate workflow)
Format (touched files only), Repository Structure, Zerocode RPC Boundary, Lint, Check x2, Test, Security, CI Required Gate.
Not run on PRs: Windows/macOS, Nix, Docker smoke, MSRV, 32-bit, benches, plugin backends, Landlock, postgres.

## Known baseline failures (red on `testing` before the migration)
- Repository Structure: `.gitmodules` declares `docs/book/po` but the gitlink is absent.
- galleon-web: TypeScript errors in `CrowsNestView.tsx`.
- ~450 Rust files are not rustfmt-clean (hence the touched-files ratchet).
- `release-gate-approval.yml` and `testing-to-prerelease-pr.yml` do not parse as YAML.

sccache comes from the repo's `.cargo/config.toml` (`rustc-wrapper`); the image only ships the binary.
