#!/usr/bin/env bash
# Source-build helpers shared by the cached source-build layers.
set -euo pipefail

DIR="$(dirname "$0")"
source "${DIR}/pins.sh"
source "${DIR}/repos.sh"

BUILD_DEPS=(
	# Toolchain - removed after builds
	cmake meson
	# Wayland / graphics stack
	wayland-devel wayland-protocols-devel libxkbcommon-devel
	pixman-devel libdrm-devel mesa-libEGL-devel mesa-libgbm-devel
	libglvnd-devel cairo-devel pango-devel
	pugixml-devel iniparser-devel
	libseat-devel libinput-devel libdisplay-info-devel hwdata
	systemd-devel
	# wiremix's bindgen step needs the unversioned libclang.so symlink.
	clang-devel
	libjpeg-turbo-devel libwebp-devel libpng-devel librsvg2-devel
	libjxl-devel libheif-devel file-devel
	tomlplusplus-devel libzip-devel
	muParser-devel re2-devel libuuid-devel
	libxcb-devel xcb-util-wm-devel xcb-util-errors-devel libXcursor-devel
	protobuf-compiler
	sdbus-cpp-devel pam-devel pipewire-devel
	# Rust/Cargo (walker, wiremix, hyprland-preview-share-picker) - removed
	# after builds
	rust cargo lz4-devel
	# walker requires gtk4-layer-shell + poppler-glib
	gtk4-devel gtk4-layer-shell-devel poppler-glib-devel
	# Go (elephant + providers) - removed after builds
	golang
	# uwsm man pages
	scdoc
	# Qt6 (hyprland-qt-support, hyprpolkitagent) - removed after builds
	qt6-qtbase-devel qt6-qtdeclarative-devel
	polkit-devel polkit-qt6-1-devel
)

# Removing -devel libs triggers a cascade into flatpak/gtk, so only
# strip the pure toolchain executables.
BUILD_TOOLCHAIN=(cmake meson rust cargo golang scdoc clang-devel qt6-qtbase-devel qt6-qtdeclarative-devel)

source_build_setup() {
	dnf5 -y install --setopt=install_weak_deps=False "${BUILD_DEPS[@]}"
}

source_build_cleanup() {
	dnf5 -y remove --no-autoremove "${BUILD_TOOLCHAIN[@]}"
}

source_build_init_workdir() {
	BUILD_WORK="$(mktemp -d)"
	export BUILD_WORK

	# Redirect cargo/go caches into the ephemeral build dir.
	# /root is a dangling symlink in bootc/ostree images, so the default $HOME/.cargo fails.
	export CARGO_HOME="${BUILD_WORK}/.cargo"
	export RUSTUP_HOME="${BUILD_WORK}/.rustup"
	export GOPATH="${BUILD_WORK}/go"
	export GOCACHE="${BUILD_WORK}/.gocache"
}

source_build_free_workdir() {
	rm -rf "${BUILD_WORK}"
}

cmake_build_install() {
	local name="$1" tag="$2"
	shift 2
	local git_args=()
	while [[ "$1" == --* ]]; do
		git_args+=("$1")
		shift
	done
	local url="$1"
	shift
	git clone --depth 1 --branch "${tag}" "${git_args[@]}" "${url}" "${BUILD_WORK}/${name}"
	cmake -S "${BUILD_WORK}/${name}" -B "${BUILD_WORK}/${name}/build" \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_INSTALL_PREFIX=/usr \
		-DCMAKE_INSTALL_LIBDIR=lib64 \
		"$@"
	cmake --build "${BUILD_WORK}/${name}/build" -j"$(nproc)"
	cmake --install "${BUILD_WORK}/${name}/build"
}

cargo_install() {
	local name="$1" tag="$2" repo="$3"
	shift 3
	git clone --depth 1 --branch "${tag}" "${repo}" "${BUILD_WORK}/${name}"
	cargo build --release --manifest-path "${BUILD_WORK}/${name}/Cargo.toml"
	for bin in "$@"; do
		install -Dm755 "${BUILD_WORK}/${name}/target/release/${bin}" "/usr/bin/${bin}"
	done
}
