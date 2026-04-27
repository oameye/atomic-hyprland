#!/usr/bin/env bash
# Build satellite tools (cargo, go, misc utilities, fonts).
set -euo pipefail

DIR="$(dirname "$0")"
source "${DIR}/source-builds.sh"

source_build_init_workdir

# Satellite tools (CMake)
cmake_build_install hyprlock "${HYPRLOCK_TAG}" https://github.com/hyprwm/hyprlock.git
cmake_build_install hypridle "${HYPRIDLE_TAG}" https://github.com/hyprwm/hypridle.git
cmake_build_install hyprpicker "${HYPRPICKER_TAG}" https://github.com/hyprwm/hyprpicker.git
cmake_build_install hyprsunset "${HYPRSUNSET_TAG}" https://github.com/hyprwm/hyprsunset.git
cmake_build_install xdg-desktop-portal-hyprland "${XDP_HYPRLAND_TAG}" https://github.com/hyprwm/xdg-desktop-portal-hyprland.git

# Qt6 components
cmake_build_install hyprland-qt-support "${HYPR_QT_SUPPORT_TAG}" https://github.com/hyprwm/hyprland-qt-support.git -DINSTALL_QML_PREFIX=/lib64/qt6/qml
cmake_build_install hyprpolkitagent "${HYPR_POLKITAGENT_TAG}" https://github.com/hyprwm/hyprpolkitagent.git

# Cargo tools
cargo_install wiremix "${WIREMIX_TAG}" https://github.com/tsowell/wiremix.git wiremix

git clone --depth 1 --branch "${HYPRLAND_PREVIEW_SHARE_PICKER_TAG}" --recurse-submodules \
	https://github.com/WhySoBad/hyprland-preview-share-picker.git \
	"${BUILD_WORK}/hyprland-preview-share-picker"
cargo build --release --manifest-path "${BUILD_WORK}/hyprland-preview-share-picker/Cargo.toml"
install -Dm755 \
	"${BUILD_WORK}/hyprland-preview-share-picker/target/release/hyprland-preview-share-picker" \
	/usr/bin/hyprland-preview-share-picker

# Go tools
git clone --depth 1 --branch "${ELEPHANT_TAG}" https://github.com/abenz1267/elephant.git "${BUILD_WORK}/elephant"
go build -C "${BUILD_WORK}/elephant/cmd/elephant" -buildvcs=false -trimpath -o /usr/bin/elephant .

# Fonts
install -d /usr/share/fonts/jetbrains-mono-nerd
curl -fsSL "https://github.com/ryanoasis/nerd-fonts/releases/download/${NERD_FONTS_TAG}/JetBrainsMono.tar.xz" |
	tar -xJ -C /usr/share/fonts/jetbrains-mono-nerd
fc-cache -f /usr/share/fonts/jetbrains-mono-nerd

source_build_free_workdir
