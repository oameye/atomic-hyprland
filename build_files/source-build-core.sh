#!/usr/bin/env bash
# Build core hyprwm libraries
set -euo pipefail

DIR="$(dirname "$0")"
source "${DIR}/source-builds.sh"

source_build_init_workdir

cmake_build_install hyprwayland-scanner "${HYPRWAYLAND_SCANNER_TAG}" https://github.com/hyprwm/hyprwayland-scanner.git
cmake_build_install hyprutils "${HYPRUTILS_TAG}" https://github.com/hyprwm/hyprutils.git -DBUILD_TESTING=OFF
cmake_build_install hyprlang "${HYPRLANG_TAG}" https://github.com/hyprwm/hyprlang.git -DBUILD_TESTING=OFF
cmake_build_install hyprcursor "${HYPRCURSOR_TAG}" https://github.com/hyprwm/hyprcursor.git
cmake_build_install hyprgraphics "${HYPRGRAPHICS_TAG}" https://github.com/hyprwm/hyprgraphics.git -DBUILD_TESTING=OFF

source_build_free_workdir
