#!/usr/bin/env bash
# Install dependencies needed by the source-build layers.
set -euo pipefail

DIR="$(dirname "$0")"
source "${DIR}/source-builds.sh"

source_build_setup

echo "Source build dependencies installed."
