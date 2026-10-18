#!/usr/bin/env bash
# Register once (state lives in the runner-state volume), then run forever.
# RUNNER_TOKEN is only needed on first start; RUNNER_LABELS/RUNNER_NAME/REPO_URL always.
set -euo pipefail

cd /home/runner/actions-runner
state=/home/runner/runner-state

# The runner keeps its config next to the binary; persist it via symlinks.
mkdir -p "$state"
for f in .runner .credentials .credentials_rsaparams; do
  [ -e "$state/$f" ] && ln -sf "$state/$f" "$f"
done

if [ ! -s "$state/.runner" ]; then
  : "${RUNNER_TOKEN:?first start needs RUNNER_TOKEN (gh api -X POST repos/<owner>/<repo>/actions/runners/registration-token)}"
  ./config.sh --unattended --replace --ephemeral=false \
    --url "$REPO_URL" --token "$RUNNER_TOKEN" \
    --name "$RUNNER_NAME" --labels "$RUNNER_LABELS" --no-default-labels
  for f in .runner .credentials .credentials_rsaparams; do
    mv "$f" "$state/$f" && ln -sf "$state/$f" "$f"
  done
fi

export ACTIONS_RUNNER_HOOK_JOB_STARTED=/usr/local/bin/trim-target.sh
exec ./run.sh
