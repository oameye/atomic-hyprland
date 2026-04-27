#!/usr/bin/env bash
# Build satellite tools (cargo, go, meson, scripts, fonts).
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

git clone --depth 1 --branch "${WALKER_TAG}" \
	https://github.com/abenz1267/walker.git "${BUILD_WORK}/walker"
cargo build --release --manifest-path "${BUILD_WORK}/walker/Cargo.toml"
install -Dm755 "${BUILD_WORK}/walker/target/release/walker" /usr/bin/walker
install -Dm644 "${BUILD_WORK}/walker/LICENSE" /usr/share/licenses/walker/LICENSE
install -Dm644 "${BUILD_WORK}/walker/resources/config.toml" /etc/xdg/walker/config.toml
install -d /etc/xdg/walker/themes/default
cp -r "${BUILD_WORK}/walker/resources/themes/default/." /etc/xdg/walker/themes/default/

# Shell/script tools
git clone --depth 1 --branch "${HYPRSHOT_TAG}" \
	https://github.com/Gustash/Hyprshot.git "${BUILD_WORK}/hyprshot"
install -Dm755 "${BUILD_WORK}/hyprshot/hyprshot" /usr/bin/hyprshot

# Go tools
git clone --depth 1 --branch "${ELEPHANT_TAG}" https://github.com/abenz1267/elephant.git "${BUILD_WORK}/elephant"
go build -C "${BUILD_WORK}/elephant/cmd/elephant" -buildvcs=false -trimpath -o /usr/bin/elephant .
install -Dm644 "${BUILD_WORK}/elephant/LICENSE" /usr/share/licenses/elephant/LICENSE

for provider_dir in "${BUILD_WORK}/elephant/internal/providers/"*/; do
	[[ -f "${provider_dir}makefile" ]] || continue
	name="$(basename "${provider_dir}")"
	(
		cd "${provider_dir}"
		go build -buildvcs=false -buildmode=plugin -trimpath -o "${name}.so" .
	)
	install -Dm755 "${provider_dir}${name}.so" "/etc/xdg/elephant/providers/${name}.so"
done

# Meson tools
git clone --depth 1 --branch "${UWSM_TAG}" \
	https://github.com/Vladimir-csp/uwsm.git "${BUILD_WORK}/uwsm"
meson setup "${BUILD_WORK}/uwsm/build" "${BUILD_WORK}/uwsm" \
	--prefix=/usr \
	-Duwsm-app=enabled
meson install -C "${BUILD_WORK}/uwsm/build"

# xdg-terminal-exec is Omarchy's default terminal selector.
git clone --depth 1 --branch "${XDG_TERMINAL_EXEC_TAG}" \
	https://github.com/Vladimir-csp/xdg-terminal-exec.git "${BUILD_WORK}/xdg-terminal-exec"
install -Dm755 "${BUILD_WORK}/xdg-terminal-exec/xdg-terminal-exec" \
	/usr/bin/xdg-terminal-exec
install -Dm644 "${BUILD_WORK}/xdg-terminal-exec/xdg-terminals.list" \
	/usr/share/xdg-terminal-exec/xdg-terminals.list

# Fonts
install -d /usr/share/fonts/jetbrains-mono-nerd
curl -fsSL "https://github.com/ryanoasis/nerd-fonts/releases/download/${NERD_FONTS_TAG}/JetBrainsMono.tar.xz" |
	tar -xJ -C /usr/share/fonts/jetbrains-mono-nerd
fc-cache -f /usr/share/fonts/jetbrains-mono-nerd

source_build_free_workdir
