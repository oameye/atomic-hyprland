#!/usr/bin/env bash
set -euo pipefail

BUILD_DEPS=(
    # Toolchain — removed after builds
    cmake meson
    # Wayland / graphics stack
    wayland-devel wayland-protocols-devel libxkbcommon-devel
    pixman-devel libdrm-devel mesa-libEGL-devel mesa-libgbm-devel
    libglvnd-devel cairo-devel pango-devel
    pugixml-devel iniparser-devel
    libseat-devel libinput-devel libdisplay-info-devel hwdata
    systemd-devel
    libjpeg-turbo-devel libwebp-devel libpng-devel librsvg2-devel
    libjxl-devel libheif-devel file-devel
    tomlplusplus-devel libzip-devel
    muParser-devel re2-devel libuuid-devel
    libxcb-devel xcb-util-wm-devel xcb-util-errors-devel libXcursor-devel
    sdbus-cpp-devel pam-devel pipewire-devel
    # Rust/Cargo (awww, swww, satty) — removed after builds
    rust cargo lz4-devel
    # satty requires GTK4 + libadwaita
    gtk4-devel libadwaita-devel
    # Go (cliphist, nwg-look) + CGo GTK3 (nwg-look) — removed after builds
    golang gtk3-devel
    # Qt6 (hyprland-qt-support, hyprpolkitagent) — removed after builds
    qt6-qtbase-devel qt6-qtdeclarative-devel
    polkit-devel polkit-qt6-1-devel
)

# Removing -devel libs triggers a cascade into flatpak/gtk/ghostty, so only
# strip the pure toolchain executables.
BUILD_TOOLCHAIN=(cmake meson rust cargo golang qt6-qtbase-devel qt6-qtdeclarative-devel)

dnf5 -y install --setopt=install_weak_deps=False "${BUILD_DEPS[@]}"

BUILD_WORK=$(mktemp -d)

# Redirect cargo/go caches into the ephemeral build dir.
# /root is a dangling symlink in bootc/ostree images, so the default $HOME/.cargo fails.
export CARGO_HOME="${BUILD_WORK}/.cargo"
export RUSTUP_HOME="${BUILD_WORK}/.rustup"
export GOPATH="${BUILD_WORK}/go"
export GOCACHE="${BUILD_WORK}/.gocache"

cmake_build_install() {
    local name="$1" tag="$2"
    shift 2
    local git_args=()
    while [[ "$1" == --* ]]; do git_args+=("$1"); shift; done
    local url="$1"; shift
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
    local name="$1" tag="$2" repo="$3"; shift 3
    git clone --depth 1 --branch "${tag}" "${repo}" "${BUILD_WORK}/${name}"
    cargo build --release --manifest-path "${BUILD_WORK}/${name}/Cargo.toml"
    for bin in "$@"; do
        install -Dm755 "${BUILD_WORK}/${name}/target/release/${bin}" "/usr/bin/${bin}"
    done
}

# ── hyprwm core libs ────────────────────────────────────────────────
cmake_build_install hyprwayland-scanner "${HYPRWAYLAND_SCANNER_TAG}" \
    https://github.com/hyprwm/hyprwayland-scanner.git

cmake_build_install hyprutils "${HYPRUTILS_TAG}" \
    https://github.com/hyprwm/hyprutils.git \
    -DBUILD_TESTING=OFF

cmake_build_install hyprlang "${HYPRLANG_TAG}" \
    https://github.com/hyprwm/hyprlang.git \
    -DBUILD_TESTING=OFF

cmake_build_install hyprcursor "${HYPRCURSOR_TAG}" \
    https://github.com/hyprwm/hyprcursor.git

cmake_build_install hyprgraphics "${HYPRGRAPHICS_TAG}" \
    https://github.com/hyprwm/hyprgraphics.git \
    -DBUILD_TESTING=OFF

# Fedora's hwdata package omits the pkg-config file that aquamarine looks up.
cat >/usr/lib64/pkgconfig/hwdata.pc <<'HWDATA_PC'
prefix=/usr
datarootdir=${prefix}/share
pkgdatadir=${datarootdir}/hwdata

Name: hwdata
Description: hwdata
Version: 0
HWDATA_PC
cmake_build_install aquamarine "${AQUAMARINE_TAG}" \
    https://github.com/hyprwm/aquamarine.git \
    -DBUILD_TESTING=OFF

# hyprland-protocols uses meson, not cmake.
git clone --depth 1 --branch "${HYPRLAND_PROTOCOLS_TAG}" \
    https://github.com/hyprwm/hyprland-protocols.git "${BUILD_WORK}/hyprland-protocols"
meson setup "${BUILD_WORK}/hyprland-protocols/build" "${BUILD_WORK}/hyprland-protocols" \
    --prefix=/usr
meson install -C "${BUILD_WORK}/hyprland-protocols/build"

cmake_build_install hyprwire "${HYPRWIRE_TAG}" \
    https://github.com/hyprwm/hyprwire.git \
    -DBUILD_TESTING=OFF

cmake_build_install glaze "${GLAZE_TAG}" \
    https://github.com/stephenberry/glaze.git \
    -Dglaze_DEVELOPER_MODE=OFF

# ── compositor ──────────────────────────────────────────────────────
# --recurse-submodules pulls bundled udis86 and hyprland-protocols fallbacks.
cmake_build_install hyprland "${HYPRLAND_TAG}" \
    --recurse-submodules \
    https://github.com/hyprwm/Hyprland.git \
    -DBUILD_TESTING=OFF

# ── toolkit ─────────────────────────────────────────────────────────
cmake_build_install hyprtoolkit "${HYPRTOOLKIT_TAG}" \
    https://github.com/hyprwm/hyprtoolkit.git

cmake_build_install hyprland-guiutils "${HYPR_GUIUTILS_TAG}" \
    https://github.com/hyprwm/hyprland-guiutils.git

# ── satellite tools ─────────────────────────────────────────────────
cmake_build_install hyprlock    "${HYPRLOCK_TAG}"   https://github.com/hyprwm/hyprlock.git
cmake_build_install hypridle    "${HYPRIDLE_TAG}"   https://github.com/hyprwm/hypridle.git
cmake_build_install hyprpaper   "${HYPRPAPER_TAG}"  https://github.com/hyprwm/hyprpaper.git
cmake_build_install hyprpicker  "${HYPRPICKER_TAG}" https://github.com/hyprwm/hyprpicker.git
cmake_build_install hyprsunset  "${HYPRSUNSET_TAG}" https://github.com/hyprwm/hyprsunset.git
cmake_build_install xdg-desktop-portal-hyprland "${XDP_HYPRLAND_TAG}" \
    https://github.com/hyprwm/xdg-desktop-portal-hyprland.git

# ── Qt6 components ──────────────────────────────────────────────────
# INSTALL_QML_PREFIX matches Fedora's Qt6 QML path.
cmake_build_install hyprland-qt-support "${HYPR_QT_SUPPORT_TAG}" \
    https://github.com/hyprwm/hyprland-qt-support.git \
    -DINSTALL_QML_PREFIX=/lib64/qt6/qml

cmake_build_install hyprpolkitagent "${HYPR_POLKITAGENT_TAG}" \
    https://github.com/hyprwm/hyprpolkitagent.git

# ── non-hyprwm tools (Cargo) ────────────────────────────────────────
cargo_install awww  "${AWWW_TAG}"  https://codeberg.org/LGFae/awww.git        awww awww-daemon
cargo_install swww  "${SWWW_TAG}"  https://github.com/LGFae/swww.git          swww swww-daemon
cargo_install satty "${SATTY_TAG}" https://github.com/gabm/Satty.git          satty

# hyprshot is a single shell script — clone the pinned tag so git verifies integrity.
git clone --depth 1 --branch "${HYPRSHOT_TAG}" \
    https://github.com/Gustash/Hyprshot.git "${BUILD_WORK}/hyprshot"
install -Dm755 "${BUILD_WORK}/hyprshot/hyprshot" /usr/bin/hyprshot

# ── non-hyprwm tools (Go) ───────────────────────────────────────────
git clone --depth 1 --branch "${CLIPHIST_TAG}" \
    https://github.com/sentriz/cliphist.git "${BUILD_WORK}/cliphist"
go build -C "${BUILD_WORK}/cliphist" -o /usr/bin/cliphist .

git clone --depth 1 --branch "${NWGLOOK_TAG}" \
    https://github.com/nwg-piotr/nwg-look.git "${BUILD_WORK}/nwg-look"
go build -C "${BUILD_WORK}/nwg-look" -o /usr/bin/nwg-look .
[[ -d "${BUILD_WORK}/nwg-look/desktop" ]] && \
    cp -r "${BUILD_WORK}/nwg-look/desktop" /usr/share/nwg-look
[[ -f "${BUILD_WORK}/nwg-look/nwg-look.desktop" ]] && \
    install -Dm644 "${BUILD_WORK}/nwg-look/nwg-look.desktop" \
        /usr/share/applications/nwg-look.desktop
[[ -d "${BUILD_WORK}/nwg-look/langs" ]] && \
    cp -r "${BUILD_WORK}/nwg-look/langs" /usr/share/nwg-look/langs

# ── non-hyprwm tools (meson) ────────────────────────────────────────
git clone --depth 1 --branch "${UWSM_TAG}" \
    https://github.com/Vladimir-csp/uwsm.git "${BUILD_WORK}/uwsm"
meson setup "${BUILD_WORK}/uwsm/build" "${BUILD_WORK}/uwsm" --prefix=/usr
meson install -C "${BUILD_WORK}/uwsm/build"

rm -rf "${BUILD_WORK}"
dnf5 -y remove --no-autoremove "${BUILD_TOOLCHAIN[@]}"
