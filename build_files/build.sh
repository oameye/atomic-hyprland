#!/usr/bin/env bash
set -euo pipefail

RELEASE="$(rpm -E %fedora)"
echo "Fedora version: ${RELEASE}"

# Pinned upstream tags / commits.
SDDM_HYPRLAND_TAG="v0.48.0"
SDDM_ASTRONAUT_COMMIT="d73842c"
SDDM_ASTRONAUT_VARIANT="astronaut"

# hyprland-guiutils (successor to the archived hyprland-qtutils) is built
# from source — the COPR doesn't package it yet. It uses hyprtoolkit
# (Wayland-native), not Qt6, so it has no private-ABI issues. As of
# v0.2.1 it requires hyprtoolkit>=0.4.0 and hyprutils>=0.10.2, newer than
# what the solopasha COPR ships, so the full hyprwm toolkit dependency
# chain (hyprwayland-scanner → hyprutils → hyprgraphics → aquamarine →
# hyprtoolkit) is also source-built below.
HYPR_GUIUTILS_TAG="v0.2.1"
HYPRWAYLAND_SCANNER_TAG="v0.4.5"
HYPRUTILS_TAG="v0.12.0"
HYPRGRAPHICS_TAG="v0.5.1"
AQUAMARINE_TAG="v0.10.0"
HYPRTOOLKIT_TAG="v0.5.3"

# awww — preferred wallpaper daemon for Hyprland-Dots (swww is the fallback).
# Not packaged in any COPR; built from source with cargo.
AWWW_TAG="v0.12.0"

# hyprland-qt-support + hyprpolkitagent — built from source against the system
# Qt6 to sidestep the solopasha COPR's Qt6.9/6.10 private-ABI mismatch.
HYPR_QT_SUPPORT_TAG="v0.1.0"
HYPR_POLKITAGENT_TAG="v0.1.3"

############################################
# 1. Enable COPR repos
#    solopasha/hyprland, pgdev/ghostty, errornointernet/quickshell stay
#    live so rpm-ostree upgrade can pick up updates between CI rebuilds.
############################################
for i in solopasha/hyprland pgdev/ghostty errornointernet/quickshell; do
    owner="${i%%/*}"
    repo="${i##*/}"
    curl -fsSL \
        "https://copr.fedorainfracloud.org/coprs/${owner}/${repo}/repo/fedora-${RELEASE}/${owner}-${repo}-fedora-${RELEASE}.repo" \
        -o "/etc/yum.repos.d/_copr_${owner}-${repo}.repo"
done

############################################
# 1b. copr_install_isolated helper (copied verbatim from
#     ublue-os/bluefin -> build_files/shared/copr-helpers.sh).
#     Enables a COPR, disables it, then installs packages from the
#     disabled COPR via --enablerepo in one transaction. Leaves no
#     .repo file live for the end-user.
############################################
copr_install_isolated() {
    local copr_name="$1"
    shift
    local packages=("$@")
    local repo_id="copr:copr.fedorainfracloud.org:${copr_name//\//:}"

    dnf5 -y copr enable "$copr_name"
    dnf5 -y copr disable "$copr_name"
    dnf5 -y install --setopt=install_weak_deps=False \
        --enablerepo="$repo_id" "${packages[@]}"
}

############################################
# 2. VS Code repo
############################################
cat > /etc/yum.repos.d/vscode.repo <<'EOF'
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF

############################################
# 3. Docker CE repo -- added but disabled by default (uBlue pattern)
############################################
dnf5 config-manager addrepo --from-repofile=https://download.docker.com/linux/fedora/docker-ce.repo
sed -i 's/^enabled=.*/enabled=0/g' /etc/yum.repos.d/docker-ce.repo

echo "Repos enabled."

############################################
# 4. Install the full package set
#    --setopt=install_weak_deps=False for image-size reduction.
############################################
PACKAGES=(
    # Hyprland ecosystem (solopasha COPR).
    # hyprland-guiutils, hyprland-qt-support, and hyprpolkitagent are built
    # from source in section 6 — the COPR versions of hyprland-qt-support /
    # hyprpolkitagent are built against Qt6.9 private API while Fedora 43
    # ships Qt6.10. Building from source compiles against the system Qt6.
    hyprland hyprlock hypridle hyprpaper hyprshot hyprpicker hyprcursor
    hyprsunset xdg-desktop-portal-hyprland
    swww

    # Session / greeter (Qt6 only -- we avoid Qt5).
    # Keyitdev/sddm-astronaut-theme is cloned into /usr/share/sddm/themes/
    # later in this build; it needs qt6-qtvirtualkeyboard + qt6-qtmultimedia +
    # qt6-qtsvg. layer-shell-qt (Qt6) is required by sddm-hyprland for
    # compositor-hosted greeter rendering.
    sddm layer-shell-qt
    qt6-qtsvg qt6-qtmultimedia qt6-qtdeclarative qt6-qtvirtualkeyboard

    # Desktop apps (Hyprland-Dots expected runtime -- compiled against
    # LinuxBeginnings/Fedora-Hyprland's install-scripts package list).
    # Deliberately skipped from that upstream list:
    #   - xfce-polkit + mate-polkit (hyprpolkitagent replaces, built in §6)
    #   - thunar + thunar-archive-plugin (we ship nautilus; $files patched
    #     to nautilus at build time)
    #   - rofi (we have rofi-wayland which provides the rofi binary)
    #   - asusctl, rog-control-center, nm-tray (ASUS / Ubuntu)
    #   - yazi (not in F43 repos -- install via brew)
    # kitty stays alongside ghostty so Kitty_themes.sh + theme switcher work.
    # ghostty is the $term default (patched into 01-UserDefaults.conf below).
    ghostty kitty waybar rofi-wayland swaync quickshell
    nautilus nautilus-python ffmpegthumbnailer xarchiver
    wl-clipboard cliphist
    grim slurp satty swappy
    network-manager-applet blueman bluez-tools python3-cairo
    pavucontrol playerctl pamixer pulseaudio-utils
    pipewire-alsa pipewire-utils
    mpv mpv-mpris cava
    xdg-desktop-portal-gtk polkit
    brightnessctl ddcutil wlr-randr uwsm wlogout
    nwg-look loupe gtk-murrine-engine
    gvfs gvfs-mtp gvfs-smb
    xdg-user-dirs xdg-utils yad libnotify acpi inxi
    dbus-tools bc ImageMagick jq nano rsync unzip wget2
    python3-requests python3-pyquery python3-pip
    btop nvtop fastfetch gnome-system-monitor qalculate-gtk
    qt5ct qt6ct qt6-qt5compat kvantum-qt5

    # Developer tooling.
    # eduvpn-client dropped -- not in F43 repos; install post-boot via
    # pipx (eduvpn-gui) or Flatpak.
    # python3-pip already listed under Desktop apps (Hyprland-Dots scripts
    # need it at runtime).
    code
    make
    gcc-c++ libstdc++-devel sqlite-devel

    # Container stack (Fedora-side).
    podman-compose podman-tui podman-machine flatpak-builder

    # GPU compute (AMD ROCm).
    rocm-hip rocm-opencl rocm-smi

    # Fonts and theming (aligned with upstream Hyprland-Dots fonts.sh).
    # Nerd Fonts installed via copr_install_isolated(che/nerd-fonts) below.
    # bibata-cursor-themes dropped -- not in F43 repos; HyDE ships cursor
    # themes into ~/.icons via its post-install.
    fontawesome-fonts-all
    google-noto-emoji-fonts google-noto-color-emoji-fonts google-noto-sans-cjk-fonts
    liberation-fonts jetbrains-mono-fonts
    adobe-source-code-pro-fonts fira-code-fonts google-droid-sans-fonts
    adwaita-icon-theme papirus-icon-theme
    kvantum
)

dnf5 -y install --setopt=install_weak_deps=False "${PACKAGES[@]}"

# Docker CE -- from the disabled docker-ce-stable repo (uBlue pattern)
dnf5 -y install --setopt=install_weak_deps=False --enablerepo=docker-ce-stable \
    docker-ce docker-ce-cli docker-compose-plugin docker-buildx-plugin containerd.io

# Nerd Fonts -- che/nerd-fonts mega-package, isolated install so the COPR
# does not stay enabled in the final image. Matches uBlue Bluefin pattern.
copr_install_isolated "che/nerd-fonts" "nerd-fonts"

# Bazaar -- Universal Blue's GTK4/libadwaita app store (Flathub browser +
# bootc-aware). Also pull uupd (Universal Update Daemon) in the same
# isolated transaction since both live in ublue-os/packages COPR.
copr_install_isolated "ublue-os/packages" "bazaar" "uupd"

# wallust -- color scheme generator from wallpapers, core of the Hyprland-Dots
# theming pipeline. Isolated install from errornointernet/packages COPR
# (same pattern as JaKooLit/Fedora-Hyprland).
copr_install_isolated "errornointernet/packages" "wallust"

echo "Packages installed."

############################################
# 5. Remove Firefox -- user installs Zen Browser Flatpak instead
############################################
rpm-ostree override remove firefox firefox-langpacks || true
# `|| true` -- base-main may not ship Firefox in all variants; tolerate absence.

############################################
# 6. Source builds (hyprland-guiutils, awww, hyprland-qt-support,
#    hyprpolkitagent). See DESIGN.md -> "Source builds" for rationale.
############################################
# BUILD_DEPS are installed for the source builds below. The heavy
# toolchain bits (cmake, rust, cargo, qt6-*-devel) are removed again at the
# end of section 6; the smaller -devel libs are left in place because
# removing them triggers a large Requires cascade (see DESIGN.md).
BUILD_DEPS=(
    # Common toolchain -- removed at end
    cmake
    # hyprwm toolkit chain (hyprwayland-scanner, hyprutils, hyprgraphics,
    # aquamarine, hyprtoolkit) + hyprland-guiutils.
    # hyprutils-devel/hyprtoolkit-devel intentionally NOT listed: the COPR
    # versions are too old for hyprland-guiutils v0.2.1, so we source-build
    # them here and let our builds provide the pkg-config files.
    hyprlang-devel
    wayland-devel wayland-protocols-devel libxkbcommon-devel
    pixman-devel libdrm-devel mesa-libEGL-devel mesa-libgbm-devel
    libglvnd-devel cairo-devel pango-devel
    pugixml-devel iniparser-devel
    libseat-devel libinput-devel libdisplay-info-devel hwdata
    systemd-devel
    libjpeg-turbo-devel libwebp-devel libpng-devel librsvg2-devel
    libjxl-devel libheif-devel file-devel
    # awww (Rust/Cargo) -- rust+cargo removed at end
    rust cargo lz4-devel
    # hyprland-qt-support + hyprpolkitagent (Qt6/CMake) -- removed at end
    qt6-qtbase-devel qt6-qtdeclarative-devel
    polkit-devel polkit-qt6-1-devel
)
# Heavy toolchain bits that are safe to strip after the builds. Removing
# the library -devel packages triggers a huge `Requires` cascade (flatpak,
# gtk*, ghostty, …), so leave those alone.
BUILD_TOOLCHAIN=(
    cmake
    rust cargo
    qt6-qtbase-devel qt6-qtdeclarative-devel
)
dnf5 -y install --setopt=install_weak_deps=False "${BUILD_DEPS[@]}"

BUILD_WORK=$(mktemp -d)

# Helper: clone + cmake configure/build/install into /usr. Used for the
# whole hyprwm toolkit chain below.
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

# 6a. hyprwayland-scanner — codegen tool used by aquamarine and hyprtoolkit.
cmake_build_install hyprwayland-scanner "${HYPRWAYLAND_SCANNER_TAG}" \
    https://github.com/hyprwm/hyprwayland-scanner.git

# 6b. hyprutils — common C++ utilities, required by the rest of the chain.
cmake_build_install hyprutils "${HYPRUTILS_TAG}" \
    https://github.com/hyprwm/hyprutils.git \
    -DBUILD_TESTING=OFF

# 6c. hyprgraphics — image/graphics helpers used by hyprtoolkit.
cmake_build_install hyprgraphics "${HYPRGRAPHICS_TAG}" \
    https://github.com/hyprwm/hyprgraphics.git \
    -DBUILD_TESTING=OFF

# 6d. aquamarine — wlroots-style backend library used by hyprtoolkit.
#     Fedora's `hwdata` package does not ship a pkg-config file (unlike Arch),
#     but aquamarine looks one up to locate `pci.ids`. Synthesize a minimal
#     .pc pointing at Fedora's /usr/share/hwdata directory.
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

# 6e. hyprtoolkit — Wayland-native GUI toolkit powering hyprland-guiutils.
cmake_build_install hyprtoolkit "${HYPRTOOLKIT_TAG}" \
    https://github.com/hyprwm/hyprtoolkit.git

# 6f. hyprland-guiutils — successor to the archived hyprland-qtutils.
#     Provides hyprland-dialog etc. Uses hyprtoolkit (Wayland-native), not Qt6.
cmake_build_install hyprland-guiutils "${HYPR_GUIUTILS_TAG}" \
    https://github.com/hyprwm/hyprland-guiutils.git

# 6g. awww — preferred wallpaper daemon for Hyprland-Dots (swww is fallback).
#     Not packaged in any COPR; built from source with cargo.
#     `/root` is a dangling symlink (→ /var/roothome) in bootc/ostree base
#     images, so cargo can't create its default `$HOME/.cargo`. Pin CARGO_HOME
#     and RUSTUP_HOME into the ephemeral build dir instead.
export CARGO_HOME="${BUILD_WORK}/.cargo"
export RUSTUP_HOME="${BUILD_WORK}/.rustup"
git clone --depth 1 --branch "${AWWW_TAG}" \
    https://codeberg.org/LGFae/awww.git "${BUILD_WORK}/awww"
cargo build --release --manifest-path "${BUILD_WORK}/awww/Cargo.toml"
install -Dm755 "${BUILD_WORK}/awww/target/release/awww" /usr/bin/awww
install -Dm755 "${BUILD_WORK}/awww/target/release/awww-daemon" /usr/bin/awww-daemon

# 6h. hyprland-qt-support — QML style plugin. Runtime dep for hyprpolkitagent.
#     INSTALL_QML_PREFIX=/lib64/qt6/qml matches Fedora's Qt6 QML install path.
cmake_build_install hyprland-qt-support "${HYPR_QT_SUPPORT_TAG}" \
    https://github.com/hyprwm/hyprland-qt-support.git \
    -DINSTALL_QML_PREFIX=/lib64/qt6/qml

# 6i. hyprpolkitagent — Hyprland-native polkit authentication agent.
cmake_build_install hyprpolkitagent "${HYPR_POLKITAGENT_TAG}" \
    https://github.com/hyprwm/hyprpolkitagent.git

rm -rf "${BUILD_WORK}"
echo "Source builds complete (hyprwm toolkit chain, hyprland-guiutils, awww, hyprland-qt-support, hyprpolkitagent)."

# Build-only toolchains do not belong in the final image. Strip only the
# heavy ones; removing the -devel libs cascades into flatpak/gtk/etc.
dnf5 -y remove --no-autoremove "${BUILD_TOOLCHAIN[@]}"

############################################
# 7. SDDM Wayland-compositor integration (sddm-hyprland) + theme.
############################################
WORK=$(mktemp -d)

# Compositor integration.
git clone --depth 1 --branch "${SDDM_HYPRLAND_TAG}" \
    https://github.com/HyDE-Project/sddm-hyprland.git "${WORK}/sddm-hyprland"
make -C "${WORK}/sddm-hyprland" install PREFIX=/usr

# Theme: clone into /usr/share/sddm/themes, pinned to a commit.
git clone https://github.com/keyitdev/sddm-astronaut-theme.git \
    /usr/share/sddm/themes/sddm-astronaut-theme
git -C /usr/share/sddm/themes/sddm-astronaut-theme reset --hard "${SDDM_ASTRONAUT_COMMIT}"
rm -rf /usr/share/sddm/themes/sddm-astronaut-theme/.git

# Copy the theme's fonts to a system font dir so the greeter can use them.
cp -r /usr/share/sddm/themes/sddm-astronaut-theme/Fonts/* /usr/share/fonts/

# Pick the variant by pointing metadata.desktop at the right config file.
sed -i "s|^ConfigFile=.*|ConfigFile=Themes/${SDDM_ASTRONAUT_VARIANT}.conf|" \
    /usr/share/sddm/themes/sddm-astronaut-theme/metadata.desktop

############################################
# 7b. LinuxBeginnings/Hyprland-Dots -- full rice, baked into /etc/skel.
############################################
git clone --depth 1 https://github.com/LinuxBeginnings/Hyprland-Dots.git \
    "${WORK}/hyprland-dots"

mkdir -p /etc/skel/.config
cp -a "${WORK}/hyprland-dots/config/." /etc/skel/.config/

# Override default apps: make ghostty the default terminal (Hyprland-Dots
# ships kitty) and nautilus the default file manager (upstream uses thunar
# which we don't install). Both are defined as $term / $files in
# 01-UserDefaults.conf; changing them there propagates to every keybind
# and waybar module that references them.
# shellcheck disable=SC2016  # $term / $files are literal Hyprland config syntax.
sed -i -e 's|^\$term\s*=.*|$term = ghostty|' \
       -e 's|^\$files\s*=.*|$files = nautilus|' \
    /etc/skel/.config/hypr/UserConfigs/01-UserDefaults.conf

rm -rf "${WORK}"

############################################
# 8. Flathub remote system-wide
############################################
flatpak remote-add --if-not-exists --system flathub \
    https://dl.flathub.org/repo/flathub.flatpakrepo

############################################
# 9. Enable systemd units at build time
############################################
systemctl enable sddm.service
systemctl enable docker.socket
systemctl enable podman.socket
systemctl enable flatpak-system-update.timer
systemctl enable podman-auto-update.timer
systemctl --global enable flatpak-user-update.timer
systemctl --global enable podman-auto-update.timer
systemctl enable atomic-hyprland-dx-groups.service
# flatpak-preinstall.service hashes /usr/share/flatpak/preinstall.d/*.preinstall
# and only runs `flatpak preinstall -y` when that manifest changes. We ship
# zen-browser there. Adding more apps later is dropping another .preinstall file.
systemctl enable flatpak-preinstall.service
# uupd timer runs the universal updater (rpm-ostree + flatpak + brew) on a
# schedule. `uupd` command is also available for manual runs.
systemctl enable uupd.timer

############################################
# 10. Cleanup for image-size hygiene AND bootc var-tmpfiles lint.
#    bootc wants /var empty in the image -- clean dnf repo metadata,
#    blueman state dir, and tmp.
############################################
dnf5 clean all
rm -rf \
    /var/cache/dnf \
    /var/cache/libdnf5 \
    /var/lib/dnf \
    /var/lib/blueman \
    /tmp/* \
    /var/tmp/*

echo "Build complete."
