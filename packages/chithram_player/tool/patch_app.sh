#!/usr/bin/env bash
# CI only. The app (not owned by spike/player) doesn't depend on chithram_player
# yet, so the spike job adds the dependency (and integration_test) in the
# checkout. Nothing is committed. Run from the repo root.
set -euo pipefail
cd app
flutter pub add chithram_player --path ../packages/chithram_player
flutter pub add 'dev:integration_test:{"sdk":"flutter"}'
mkdir -p integration_test
cp ../packages/chithram_player/integration_test/*.dart integration_test/
