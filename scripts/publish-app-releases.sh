#!/usr/bin/env bash
set -euo pipefail

# All callers share the ios-distribution concurrency group; preserve pointer history.
git fetch origin testflight-latest
release_worktree=$(mktemp -d)
git worktree add --detach "$release_worktree" FETCH_HEAD
trap 'git worktree remove --force "$release_worktree"' EXIT

FITFIGHT_RELEASE_STATE_DIR="$release_worktree" bundle exec fastlane refresh_app_releases
git -C "$release_worktree" add builds.json releases.json latest.json
if git -C "$release_worktree" diff --cached --quiet; then
  exit 0
fi
git -C "$release_worktree" \
  -c user.name="github-actions[bot]" \
  -c user.email="41898282+github-actions[bot]@users.noreply.github.com" \
  commit -m "Refresh available FitFight releases"
git -C "$release_worktree" push origin HEAD:testflight-latest
