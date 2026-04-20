#!/usr/bin/env bash
set -euo pipefail

PACKAGES=(
    # Greeter — omarchy ships a Qt Quick SDDM theme. Needs qtdeclarative (QtQuick)
    # and qtsvg (for the logo.svg).
    sddm
    qt6-qtsvg qt6-qtdeclarative

    # Desktop — matches the omarchy expected runtime.
    # walker (launcher) + elephant (walker data provider) are source-built.
    ghostty waybar mako
    swaybg swayosd fcitx5
    gnome-calculator polkit-gnome
    nautilus nautilus-python ffmpegthumbnailer xarchiver
    tmux imv starship neovim
    wl-clipboard
    grim slurp swappy gpu-screen-recorder
    network-manager-applet iwd blueman bluez-tools python3-cairo
    pavucontrol playerctl pamixer pulseaudio-utils
    pipewire-alsa pipewire-utils
    mpv mpv-mpris cava
    # Printing (omarchy config/hardware/printer.sh) + mDNS discovery
    cups cups-browsed avahi nss-mdns
    # AMD Vulkan (gaming)
    mesa-vulkan-drivers
    # Plymouth boot splash (omarchy ships its own theme)
    plymouth plymouth-plugin-label plymouth-plugin-script
    xdg-desktop-portal-gtk polkit
    brightnessctl ddcutil wlr-randr wlogout
    loupe gtk-murrine-engine
    gvfs gvfs-mtp gvfs-smb
    xdg-user-dirs xdg-utils yad libnotify acpi inxi
    dbus-tools bc ImageMagick jq nano rsync unzip wget2
    python3-requests python3-pyquery python3-pip
    btop nvtop fastfetch gnome-system-monitor qalculate-gtk
    qt5ct qt6ct qt6-qt5compat kvantum-qt5

    # Developer tooling
    code
    make gcc-c++ libstdc++-devel sqlite-devel

    # Containers
    podman-compose podman-tui podman-machine flatpak-builder

    # ROCm (AMD GPU compute)
    rocm-hip rocm-opencl rocm-smi

    # Fonts and theming — nerd-fonts installed via copr_install_isolated below.
    fontawesome-fonts-all
    google-noto-emoji-fonts google-noto-color-emoji-fonts google-noto-sans-cjk-fonts
    liberation-fonts jetbrains-mono-fonts
    adobe-source-code-pro-fonts fira-code-fonts google-droid-sans-fonts
    adwaita-icon-theme papirus-icon-theme
    kvantum
)

dnf5 -y install --setopt=install_weak_deps=False "${PACKAGES[@]}"

dnf5 -y install --setopt=install_weak_deps=False --enablerepo=docker-ce-stable \
    docker-ce docker-ce-cli docker-compose-plugin docker-buildx-plugin containerd.io

# tte (terminaltexteffects) — Python 3 CLI used by omarchy-launch-screensaver.
# Not packaged for Fedora; install from PyPI system-wide into /usr. Because we
# own the distribution we can safely use --break-system-packages here.
pip3 install --prefix=/usr --break-system-packages --no-cache-dir \
    terminaltexteffects

copr_install_isolated "che/nerd-fonts" "nerd-fonts"
copr_install_isolated "ublue-os/packages" "bazaar" "uupd"
copr_install_isolated "errornointernet/packages" "wallust"

rpm-ostree override remove firefox firefox-langpacks || true
