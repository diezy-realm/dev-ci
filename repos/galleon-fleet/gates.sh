#!/usr/bin/env bash
# galleon-fleet gate definitions (per-repo; the poller in bin/ci-poller is generic).
#   gates.sh list        -> one line per gate: name|tier|net|limit_min|advisory
#   gates.sh run <name>  -> run that gate inside the CI container, cwd = PR checkout
# tier:     guard = cheap, heavy = compile/test (skipped when a guard is red)
# net:      none = container has no network, full = bridge (advisory DBs, fetch)
# advisory: 1 = reported but never blocks the aggregate / auto-merge
# Env from the poller: BASE (target branch, e.g. testing), PR_SHA.
set -euo pipefail

LIST='Format|guard|none|10|0
Repository Structure|guard|none|10|1
Zerocode RPC Boundary|guard|none|10|0
Principle|guard|none|10|0
Lint|heavy|none|90|0
Check (no default features)|heavy|none|90|0
Check (default features, all targets)|heavy|none|90|0
Test|heavy|none|120|1
Security|heavy|full|30|0'
# Repository Structure is advisory: .gitmodules declares docs/book/po but the gitlink is absent on
# testing itself (baseline red). Make it blocking again once testing is fixed.
# Test is advisory by Owner decision 2026-10-17 (flaky nextest).

cd_pr() { cd "${PR_DIR:-/home/runner/actions-runner/_work/pr}"; }
merge_base() { git merge-base "origin/$BASE" HEAD; }
web_placeholder() { mkdir -p web/dist && touch web/dist/.gitkeep; }

has_rust_changes() {
  local files
  files=$(git diff --name-only "$(merge_base)" HEAD -- '*.rs' '*Cargo.toml' '*Cargo.lock' || true)
  [ -n "$files" ]
}

gate_format() {
  local files report f st=0
  files=$(git diff --name-only --diff-filter=AM "$(merge_base)" HEAD -- '*.rs' || true)
  [ -n "$files" ] || { echo "no .rs changes"; return 0; }
  # Ratchet: ~450 legacy files are not rustfmt-clean, so gate only files this PR touches.
  report=$(cargo fmt --all -- --check 2>&1 | grep '^Diff in' || true)
  for f in $files; do
    if grep -qF "/$f:" <<<"$report"; then echo "not rustfmt-clean: $f"; st=1; fi
  done
  return $st
}

gate_repository_structure() {
  local gitlinks declared
  gitlinks=$(git ls-files -s | awk '$1 == "160000" { print $4 }' | sort)
  declared=$( { git config --file .gitmodules --get-regexp '^submodule\..*\.path$' 2>/dev/null || true; } | awk '{ print $2 }' | sort)
  if [ "$gitlinks" != "$declared" ] || [ "$gitlinks" != "docs/book/po" ]; then
    echo "gitlinks:   [$gitlinks]"; echo ".gitmodules: [$declared]"; echo "allowed:    [docs/book/po]"
    return 1
  fi
  scripts/release/refresh-translations.test.sh
  python3 scripts/release/bump-version.test.py
  bash scripts/ci/monthly_outdated_result.test.sh
  bash scripts/ci/install_release_tool.test.sh
  bash scripts/ci/apt_install.test.sh
  python3 scripts/ci/release_attestation_contract_test.py
  bash scripts/ci/path_labeler_matrix.test.sh
  bash scripts/ci/hardware_feature_test_lane.test.sh
  bash scripts/ci/release_post_text.test.sh
}

gate_zerocode_rpc_boundary() {
  if git diff --name-only "$(merge_base)" HEAD | grep -q '^apps/zerocode/'; then
    bash scripts/ci/zerocode_no_clawcrew_dep_gate.sh
  else
    echo "apps/zerocode untouched"
  fi
}

# Union of the former "Principle Gate Reviewer" and "Principle Checklist & Standards Gate"
# workflows: they duplicated the unwrap and D-2 checks.
gate_principle() {
  local base="origin/$BASE" st=0 out
  if [ -f scripts/ci/check_production_unwrap.py ]; then
    python3 scripts/ci/check_production_unwrap.py --base "$base" || st=1
  fi
  out=$(git diff -U0 "$base...HEAD" | grep '^[+][^+]' \
        | grep -iE '((api_key|secret_key|private_key|token)\s*[:=]\s*["'"'"'][a-zA-Z0-9_\-]{16,})' || true)
  if [ -n "$out" ]; then echo "possible hardcoded secret in added lines:"; echo "$out" | cut -c1-80; st=1; fi
  if [ -f scripts/ci/check_gate_d2.py ]; then python3 scripts/ci/check_gate_d2.py || st=1; fi
  out=$(git diff --name-only --diff-filter=A "$base...HEAD" | grep 'crates/.*Cargo\.toml' || true)
  [ -z "$out" ] || echo "WARN Gate D-1: new crate manifest(s), confirm crate-split is intended: $out"
  out=$(git diff --name-only --diff-filter=A "$base...HEAD" | grep 'crates/clawcrew-.*Cargo\.toml' || true)
  [ -z "$out" ] || echo "WARN brand: new crate(s) must use galleon-: $out"
  return $st
}

gate_lint() {
  has_rust_changes || { echo "no rust changes; skipping gate"; return 0; }
  web_placeholder
  bash scripts/ci/run_clippy.test.sh
  bash scripts/ci/run_clippy.sh --scope workspace --summary-title "Lint diagnostics" --log-name cargo-clippy.log
  # clawcrew-desktop needs GTK libs the image does not carry.
  cargo doc --no-deps --workspace --exclude clawcrew-desktop
  bash scripts/ci/comment_hygiene_gate.test.sh
  bash scripts/ci/comment_hygiene_gate.sh
  bash scripts/dev/act-local.test.sh
}

gate_check_no_default_features() {
  has_rust_changes || { echo "no rust changes; skipping gate"; return 0; }
  web_placeholder
  RUSTFLAGS="-D warnings" cargo check --locked --workspace --exclude clawcrew-desktop --no-default-features
}

gate_check_default_features_all_targets() {
  has_rust_changes || { echo "no rust changes; skipping gate"; return 0; }
  web_placeholder
  RUSTFLAGS="-D warnings" cargo check --locked --workspace --exclude clawcrew-desktop --all-targets
}

gate_test() {
  has_rust_changes || { echo "no rust changes; skipping gate"; return 0; }
  web_placeholder
  export CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER=clang
  export CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_RUSTFLAGS="-C link-arg=-fuse-ld=mold"
  ./scripts/ci/firmware_protocol_gate.sh
  cargo nextest run --locked --workspace --exclude clawcrew-desktop
  cargo nextest run --locked --no-fail-fast -p clawcrew-hardware --features hardware --lib
}

gate_security() {
  python3 scripts/ci/lru_advisory_scope_test.py
  if has_rust_changes; then
    cargo deny check
    cargo verify-project && cargo fetch --locked
  else
    echo "no rust changes; skipping cargo deny / cargo verify-project"
  fi
  python3 - <<'PY'
import yaml
for p in (".github/workflows/ci.yml", ".github/workflows/windows-tests.yml",
          ".github/workflows/project-dashboard-plan.yml", ".github/workflows/pr-size-labeler.yml",
          ".github/workflows/release-stable-manual.yml"):
    yaml.safe_load(open(p)); print(p, "valid")
PY
  python3 -m unittest discover -s scripts/github -p '*_test.py'
  if has_rust_changes; then
    cargo audit
  else
    echo "no rust changes; skipping cargo audit"
  fi
}

slug() { tr '[:upper:]' '[:lower:]' <<<"$1" | sed -E 's/[^a-z0-9]+/_/g; s/^_|_$//g'; }

case "${1:-}" in
  list) echo "$LIST" ;;
  run)
    cd_pr
    fn="gate_$(slug "${2:?gate name}")"
    declare -F "$fn" >/dev/null || { echo "no such gate: $2 ($fn)" >&2; exit 2; }
    "$fn" ;;
  prepare)
    # Network-on step after the poller's `cargo fetch`: that skips standalone crates outside the root
    # workspace, but every gate runs --offline (the firmware gate inside Test needs this one).
    cd_pr
    cargo fetch --locked --manifest-path firmware/clawcrew-fw-protocol/Cargo.toml ;;
  *) echo "usage: gates.sh list | run <name> | prepare" >&2; exit 2 ;;
esac
