#!/usr/bin/env bash
set -euo pipefail

RELEASE="$(rpm -E %fedora)"
echo "Fedora version: ${RELEASE}"

# Pinned upstream tags.
# sddm-hyprland: SDDM Wayland-compositor integration (make install -> /usr/share/hypr/sddm).
# sddm-astronaut-theme: SDDM theme -- pinned to a specific commit since
# the repo has no tags.
SDDM_HYPRLAND_TAG="v0.48.0"
SDDM_ASTRONAUT_COMMIT="d73842c"
SDDM_ASTRONAUT_VARIANT="astronaut"

############################################
# 1. Enable COPR repos
#    solopasha/hyprland and pgdev/ghostty stay live so rpm-ostree upgrade
#    can pick up Hyprland/ghostty updates between CI rebuilds.
############################################
for i in solopasha/hyprland pgdev/ghostty; do
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
    # hyprpolkitagent + hyprland-qtutils are dropped: their dep
    # hyprland-qt-support-0.1.0 requires Qt6.9 private API while F43 updates
    # ships Qt6.10. mate-polkit is used as the polkit auth agent instead.
    hyprland hyprlock hypridle hyprpaper hyprshot hyprpicker hyprcursor
    hyprsunset xdg-desktop-portal-hyprland

    # Session / greeter (Qt6 only -- we avoid Qt5).
    # Keyitdev/sddm-astronaut-theme is cloned into /usr/share/sddm/themes/
    # later in this build; it needs qt6-qtvirtualkeyboard + qt6-qtmultimedia +
    # qt6-qtsvg. layer-shell-qt (Qt6) is required by sddm-hyprland for
    # compositor-hosted greeter rendering.
    sddm layer-shell-qt
    qt6-qtsvg qt6-qtmultimedia qt6-qtdeclarative qt6-qtvirtualkeyboard

    # Desktop apps.
    # kitty is kept alongside ghostty: LinuxBeginnings/Hyprland-Dots
    # references kitty as its themed reference terminal (theme switcher,
    # Kitty_themes.sh, etc.). ghostty is the actual daily driver -- user
    # sets `$term = ghostty` in ~/.config/hypr/UserConfigs/01-UserDefaults.conf
    # after running the dots installer.
    # yazi dropped -- not in F43 repos; install via brew post-boot.
    ghostty kitty waybar rofi-wayland swaync
    nautilus nautilus-python
    wl-clipboard cliphist
    grim slurp satty
    network-manager-applet blueman bluez-tools
    pavucontrol playerctl pamixer
    xdg-desktop-portal-gtk polkit mate-polkit
    brightnessctl wlr-randr uwsm
    gvfs gvfs-mtp gvfs-smb

    # Developer tooling.
    # eduvpn-client dropped -- not in F43 repos; install post-boot via
    # pipx (eduvpn-gui) or Flatpak.
    code
    make
    gcc-c++ libstdc++-devel python3-pip sqlite-devel

    # Container stack (Fedora-side).
    podman-compose podman-tui podman-machine flatpak-builder

    # GPU compute (AMD ROCm).
    rocm-hip rocm-opencl rocm-smi

    # Fonts and theming.
    # Nerd Fonts installed via copr_install_isolated(che/nerd-fonts) below.
    # bibata-cursor-themes dropped -- not in F43 repos; HyDE ships cursor
    # themes into ~/.icons via its post-install.
    fontawesome-fonts-all google-noto-emoji-fonts liberation-fonts
    jetbrains-mono-fonts
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

echo "Packages installed."

############################################
# 5. Remove Firefox -- user installs Zen Browser Flatpak instead
############################################
rpm-ostree override remove firefox firefox-langpacks || true
# `|| true` -- base-main may not ship Firefox in all variants; tolerate absence.

############################################
# 6. SDDM Wayland-compositor integration (sddm-hyprland) + theme.
#    - sddm-hyprland drops conf files + a Hyprland config into
#      /usr/share/hypr/sddm/ so the greeter renders through a Hyprland
#      compositor. Qt6-compatible.
#    - Keyitdev/sddm-astronaut-theme provides the actual look; we pick the
#      ${SDDM_ASTRONAUT_VARIANT} variant by editing metadata.desktop.
#    See DESIGN.md -> "SDDM greeter".
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
# 6b. LinuxBeginnings/Hyprland-Dots -- full rice, baked into /etc/skel.
#     Unpinned (tracks master) so weekly CI picks up upstream improvements
#     automatically. See DESIGN.md -> "Desktop Environment".
#
#     Users run `ujust sync-skel-config` post-rebase to rsync the new
#     configs into their $HOME (/etc/skel only applies to new accounts).
############################################
git clone --depth 1 https://github.com/LinuxBeginnings/Hyprland-Dots.git \
    "${WORK}/hyprland-dots"

mkdir -p /etc/skel/.config
cp -a "${WORK}/hyprland-dots/config/." /etc/skel/.config/

# Override: make ghostty the default terminal (Hyprland-Dots ships kitty).
# $term is defined once in 01-UserDefaults.conf; changing it there propagates
# to every keybind and waybar module that uses $term.
# shellcheck disable=SC2016  # $term is literal Hyprland config syntax.
sed -i 's|^\$term\s*=.*|$term = ghostty|' \
    /etc/skel/.config/hypr/UserConfigs/01-UserDefaults.conf

# Suppress the "hyprland-qtutils missing" notification overlay.
# hyprland-qtutils is not installable on F43 while solopasha's
# hyprland-qt-support-0.1.0 requires Qt6.9 private API (F43 ships Qt6.10).
# Same constraint affects cjuniorfox/hyprland-atomic. Hyprland exposes
# `misc:disable_hyprland_guiutils_check = true` specifically to quiet this
# warning when the user knows the package is intentionally absent.
# See: hyprwm/hyprland-qt-support issue #9.
cat >> /etc/skel/.config/hypr/UserConfigs/UserSettings.conf <<'EOF'

# Added by atomic-hyprland build.sh -- suppress the qtutils-missing warning.
# Remove this block if hyprland-qtutils becomes installable again.
misc {
    disable_hyprland_guiutils_check = true
}
EOF

rm -rf "${WORK}"

############################################
# 7. Flathub remote system-wide
############################################
flatpak remote-add --if-not-exists --system flathub \
    https://dl.flathub.org/repo/flathub.flatpakrepo

############################################
# 8. Enable systemd units at build time
############################################
systemctl enable sddm.service
systemctl enable docker.socket
systemctl enable podman.socket
systemctl enable flatpak-system-update.timer
systemctl enable podman-auto-update.timer
systemctl --global enable flatpak-user-update.timer
systemctl --global enable podman-auto-update.timer
systemctl enable atomic-hyprland-dx-groups.service
systemctl enable install-zen-browser.service

############################################
# 9. Cleanup for image-size hygiene AND bootc var-tmpfiles lint.
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
