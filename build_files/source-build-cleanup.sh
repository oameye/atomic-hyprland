#!/usr/bin/env bash
# Remove build toolchains after all source-build layers.
set -euo pipefail

DIR="$(dirname "$0")"
source "${DIR}/source-builds.sh"

source_build_cleanup

echo "Source build toolchains removed."
