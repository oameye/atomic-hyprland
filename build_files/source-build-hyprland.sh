#!/usr/bin/env bash
# Build Hyprland and closely related hyprwm components.
set -euo pipefail

DIR="$(dirname "$0")"
source "${DIR}/source-builds.sh"

source_build_init_workdir

# Fedora's hwdata package omits the pkg-config file that aquamarine looks up.
cat >/usr/lib64/pkgconfig/hwdata.pc <<'HWDATA_PC'
prefix=/usr
datarootdir=${prefix}/share
pkgdatadir=${datarootdir}/hwdata

Name: hwdata
Description: hwdata
Version: 0
HWDATA_PC

cmake_build_install aquamarine "${AQUAMARINE_TAG}" https://github.com/hyprwm/aquamarine.git -DBUILD_TESTING=OFF

git clone --depth 1 --branch "${HYPRLAND_PROTOCOLS_TAG}" \
	https://github.com/hyprwm/hyprland-protocols.git "${BUILD_WORK}/hyprland-protocols"
meson setup "${BUILD_WORK}/hyprland-protocols/build" "${BUILD_WORK}/hyprland-protocols" --prefix=/usr
meson install -C "${BUILD_WORK}/hyprland-protocols/build"

cmake_build_install hyprwire "${HYPRWIRE_TAG}" https://github.com/hyprwm/hyprwire.git -DBUILD_TESTING=OFF
cmake_build_install glaze "${GLAZE_TAG}" https://github.com/stephenberry/glaze.git -Dglaze_DEVELOPER_MODE=OFF

cmake_build_install hyprland "${HYPRLAND_TAG}" \
	--recurse-submodules \
	https://github.com/hyprwm/Hyprland.git \
	-DBUILD_TESTING=OFF

cmake_build_install hyprtoolkit "${HYPRTOOLKIT_TAG}" https://github.com/hyprwm/hyprtoolkit.git
cmake_build_install hyprland-guiutils "${HYPR_GUIUTILS_TAG}" https://github.com/hyprwm/hyprland-guiutils.git

source_build_free_workdir
