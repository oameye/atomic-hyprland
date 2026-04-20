#!/usr/bin/env bash
# Layer 2 of 2 — packages, desktop, systemd, cleanup.
# Repos and source-built binaries are already in the image from source-builds.sh.
set -euo pipefail

RELEASE="$(rpm -E %fedora)"

SDDM_HYPRLAND_TAG="v0.48.0"
SDDM_ASTRONAUT_COMMIT="d73842c"
SDDM_ASTRONAUT_VARIANT="astronaut"

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
# Packages
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

rpm-ostree override remove firefox firefox-langpacks || true

############################################
# SDDM Wayland-compositor integration (sddm-hyprland) + theme.
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
