#!/usr/bin/env bash
# Job-started hook: keep the shared CI target dir under a hard cap so it cannot eat the host disk.
set -eu
dir="${CARGO_TARGET_DIR:-}"
[ -n "$dir" ] && [ -d "$dir" ] || exit 0
used_gb=$(( $(du -sk "$dir" | cut -f1) / 1048576 ))
if [ "$used_gb" -ge "${CI_TARGET_MAX_GB:-60}" ]; then
  echo "trim-target: $dir is ${used_gb}G (cap ${CI_TARGET_MAX_GB:-60}G), wiping"
  find "$dir" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
fi
