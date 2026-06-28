#!/usr/bin/env bash
# Layer 1 of 2 — repos + source builds.
# Runs before the package install layer so its output is cached independently.
# Changes here (tag bumps, new source-built tools) invalidate only this layer.
set -euo pipefail

DIR="$(dirname "$0")"

source "${DIR}/pins.sh"

# ── Repos ────────────────────────────────────────────────────────────
source "${DIR}/repos.sh"

# With the hyprwm ecosystem now installed from a COPR (see packages.sh), the
# only source builds left are the non-hyprwm desktop tools: walker + the
# hyprland share picker (Rust/GTK4), wiremix (Rust/PipeWire), elephant (Go),
# and uwsm (meson). This dependency set is scoped to exactly those.
BUILD_DEPS=(
	# meson (uwsm); removed after builds
	meson
	# wiremix's bindgen step needs the unversioned libclang.so symlink, plus
	# pipewire headers for the libspa bindings.
	clang-devel pipewire-devel
	# Rust/Cargo (walker, wiremix, hyprland-preview-share-picker); removed
	# after builds
	rust cargo lz4-devel
	# walker + the share picker need gtk4-layer-shell; walker also needs
	# poppler-glib. gtk4-layer-shell-devel pulls gtk4/wayland transitively.
	gtk4-devel gtk4-layer-shell-devel poppler-glib-devel
	# Go (elephant + providers); removed after builds
	golang
	# uwsm man pages
	scdoc
)

# Removing -devel libs triggers a cascade into flatpak/gtk, so only
# strip the pure toolchain executables.
BUILD_TOOLCHAIN=(meson rust cargo golang scdoc clang-devel)

dnf5 -y install --setopt=install_weak_deps=False "${BUILD_DEPS[@]}"

BUILD_WORK="$(mktemp -d)"

# Redirect cargo/go caches into the ephemeral build dir.
# /root is a dangling symlink in bootc/ostree images, so the default $HOME/.cargo fails.
export CARGO_HOME="${BUILD_WORK}/.cargo"
export RUSTUP_HOME="${BUILD_WORK}/.rustup"
export GOPATH="${BUILD_WORK}/go"
export GOCACHE="${BUILD_WORK}/.gocache"

cargo_install() {
	local name="$1" tag="$2" repo="$3"
	shift 3
	git clone --depth 1 --branch "${tag}" "${repo}" "${BUILD_WORK}/${name}"
	cargo build --release --manifest-path "${BUILD_WORK}/${name}/Cargo.toml"
	for bin in "$@"; do
		install -Dm755 "${BUILD_WORK}/${name}/target/release/${bin}" "/usr/bin/${bin}"
	done
}

# The hyprwm ecosystem (compositor, libs, satellites, Qt6 components) is no
# longer built here; it is installed from the wayblueorg COPR in packages.sh.

# ── non-hyprwm tools (Cargo) ────────────────────────────────────────
cargo_install wiremix "${WIREMIX_TAG}" https://github.com/tsowell/wiremix.git \
	wiremix
git clone --depth 1 --branch "${HYPRLAND_PREVIEW_SHARE_PICKER_TAG}" \
	--recurse-submodules \
	https://github.com/WhySoBad/hyprland-preview-share-picker.git \
	"${BUILD_WORK}/hyprland-preview-share-picker"
cargo build --release \
	--manifest-path "${BUILD_WORK}/hyprland-preview-share-picker/Cargo.toml"
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

# hyprshot is a single shell script — clone the pinned tag so git verifies integrity.
git clone --depth 1 --branch "${HYPRSHOT_TAG}" \
	https://github.com/Gustash/Hyprshot.git "${BUILD_WORK}/hyprshot"
install -Dm755 "${BUILD_WORK}/hyprshot/hyprshot" /usr/bin/hyprshot

# ── non-hyprwm tools (Go) ───────────────────────────────────────────
git clone --depth 1 --branch "${ELEPHANT_TAG}" \
	https://github.com/abenz1267/elephant.git "${BUILD_WORK}/elephant"
go build -C "${BUILD_WORK}/elephant/cmd/elephant" -buildvcs=false -trimpath -o /usr/bin/elephant .
install -Dm644 "${BUILD_WORK}/elephant/LICENSE" /usr/share/licenses/elephant/LICENSE
# Providers are loaded as Go plugins (.so) from /etc/xdg/elephant/providers/.
# Upstream's top-level makefile only builds the main binary; each provider
# directory has its own makefile using -buildmode=plugin. Build them here
# with the same toolchain so the Go plugin ABI matches /usr/bin/elephant —
# any mismatch triggers "no plugin module data" at load time.
for provider_dir in "${BUILD_WORK}/elephant/internal/providers/"*/; do
	[[ -f "${provider_dir}makefile" ]] || continue
	name="$(basename "${provider_dir}")"
	(
		cd "${provider_dir}"
		go build -buildvcs=false -buildmode=plugin -trimpath -o "${name}.so" .
	)
	install -Dm755 "${provider_dir}${name}.so" \
		"/etc/xdg/elephant/providers/${name}.so"
done

# ── non-hyprwm tools (meson) ────────────────────────────────────────
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

# ── Fonts (upstream Nerd Fonts release) ─────────────────────────────
# Omarchy's configs reference "JetBrainsMono Nerd Font". Fedora main
# ships jetbrains-mono-fonts (non-nerd) and che/nerd-fonts only ships
# symbols-only — neither provides the patched JetBrains Mono Nerd variant.
# Pull the pre-patched release tarball from upstream, equivalent to
# Arch's ttf-jetbrains-mono-nerd package.
install -d /usr/share/fonts/jetbrains-mono-nerd
curl -fsSL "https://github.com/ryanoasis/nerd-fonts/releases/download/${NERD_FONTS_TAG}/JetBrainsMono.tar.xz" |
	tar -xJ -C /usr/share/fonts/jetbrains-mono-nerd
fc-cache -f /usr/share/fonts/jetbrains-mono-nerd

rm -rf "${BUILD_WORK}"
dnf5 -y remove --no-autoremove "${BUILD_TOOLCHAIN[@]}"

echo "Source builds complete."
