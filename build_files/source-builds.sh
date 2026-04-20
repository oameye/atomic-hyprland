#!/usr/bin/env bash
# Layer 1 of 2 — repos + source builds.
# Runs before the package install layer so its output is cached independently.
# Changes here (tag bumps, new source-built tools) invalidate only this layer.
set -euo pipefail

RELEASE="$(rpm -E %fedora)"

# Pinned source-build tags — bump to upgrade, each change invalidates this layer.
HYPR_GUIUTILS_TAG="v0.2.1"
HYPRWAYLAND_SCANNER_TAG="v0.4.5"
HYPRUTILS_TAG="v0.12.0"
HYPRGRAPHICS_TAG="v0.5.1"
AQUAMARINE_TAG="v0.10.0"
HYPRTOOLKIT_TAG="v0.5.3"
AWWW_TAG="v0.12.0"
HYPR_QT_SUPPORT_TAG="v0.1.0"
HYPR_POLKITAGENT_TAG="v0.1.3"

# ── Repos ────────────────────────────────────────────────────────────
# These .repo files persist into Layer 2 so the package install layer
# can install from solopasha/hyprland, pgdev/ghostty, etc.
for i in solopasha/hyprland pgdev/ghostty errornointernet/quickshell; do
    owner="${i%%/*}"
    repo="${i##*/}"
    curl -fsSL \
        "https://copr.fedorainfracloud.org/coprs/${owner}/${repo}/repo/fedora-${RELEASE}/${owner}-${repo}-fedora-${RELEASE}.repo" \
        -o "/etc/yum.repos.d/_copr_${owner}-${repo}.repo"
done

cat > /etc/yum.repos.d/vscode.repo <<'EOF'
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF

dnf5 config-manager addrepo \
    --from-repofile=https://download.docker.com/linux/fedora/docker-ce.repo
sed -i 's/^enabled=.*/enabled=0/g' /etc/yum.repos.d/docker-ce.repo

# ── Source builds ────────────────────────────────────────────────────
BUILD_DEPS=(
    cmake
    hyprlang-devel
    wayland-devel wayland-protocols-devel libxkbcommon-devel
    pixman-devel libdrm-devel mesa-libEGL-devel mesa-libgbm-devel
    libglvnd-devel cairo-devel pango-devel
    pugixml-devel iniparser-devel
    libseat-devel libinput-devel libdisplay-info-devel hwdata
    systemd-devel
    libjpeg-turbo-devel libwebp-devel libpng-devel librsvg2-devel
    libjxl-devel libheif-devel file-devel
    rust cargo lz4-devel
    qt6-qtbase-devel qt6-qtdeclarative-devel
    polkit-devel polkit-qt6-1-devel
)
BUILD_TOOLCHAIN=(cmake rust cargo qt6-qtbase-devel qt6-qtdeclarative-devel)

dnf5 -y install --setopt=install_weak_deps=False "${BUILD_DEPS[@]}"

BUILD_WORK=$(mktemp -d)

cmake_build_install() {
    local name="$1" tag="$2" url="$3"
    shift 3
    git clone --depth 1 --branch "${tag}" "${url}" "${BUILD_WORK}/${name}"
    cmake -S "${BUILD_WORK}/${name}" -B "${BUILD_WORK}/${name}/build" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DCMAKE_INSTALL_LIBDIR=lib64 \
        "$@"
    cmake --build "${BUILD_WORK}/${name}/build" -j"$(nproc)"
    cmake --install "${BUILD_WORK}/${name}/build"
}

cmake_build_install hyprwayland-scanner "${HYPRWAYLAND_SCANNER_TAG}" \
    https://github.com/hyprwm/hyprwayland-scanner.git

cmake_build_install hyprutils "${HYPRUTILS_TAG}" \
    https://github.com/hyprwm/hyprutils.git \
    -DBUILD_TESTING=OFF

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

cmake_build_install hyprtoolkit "${HYPRTOOLKIT_TAG}" \
    https://github.com/hyprwm/hyprtoolkit.git

cmake_build_install hyprland-guiutils "${HYPR_GUIUTILS_TAG}" \
    https://github.com/hyprwm/hyprland-guiutils.git

# /root is a dangling symlink in bootc/ostree images; redirect cargo caches.
export CARGO_HOME="${BUILD_WORK}/.cargo"
export RUSTUP_HOME="${BUILD_WORK}/.rustup"
git clone --depth 1 --branch "${AWWW_TAG}" \
    https://codeberg.org/LGFae/awww.git "${BUILD_WORK}/awww"
cargo build --release --manifest-path "${BUILD_WORK}/awww/Cargo.toml"
install -Dm755 "${BUILD_WORK}/awww/target/release/awww" /usr/bin/awww
install -Dm755 "${BUILD_WORK}/awww/target/release/awww-daemon" /usr/bin/awww-daemon

cmake_build_install hyprland-qt-support "${HYPR_QT_SUPPORT_TAG}" \
    https://github.com/hyprwm/hyprland-qt-support.git \
    -DINSTALL_QML_PREFIX=/lib64/qt6/qml

cmake_build_install hyprpolkitagent "${HYPR_POLKITAGENT_TAG}" \
    https://github.com/hyprwm/hyprpolkitagent.git

rm -rf "${BUILD_WORK}"
dnf5 -y remove --no-autoremove "${BUILD_TOOLCHAIN[@]}"

echo "Source builds complete."
