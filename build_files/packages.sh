#!/usr/bin/env bash
set -euo pipefail

PACKAGES=(
    # Greeter — Qt6 only; sddm-astronaut-theme needs these Qt6 modules.
    # layer-shell-qt is required by sddm-hyprland for compositor-hosted rendering.
    sddm layer-shell-qt
    qt6-qtsvg qt6-qtmultimedia qt6-qtdeclarative qt6-qtvirtualkeyboard

    # Desktop — matches the Hyprland-Dots expected runtime.
    # kitty stays alongside ghostty because Hyprland-Dots' theme switcher references it.
    # rofi-wayland provides the rofi binary; polkit agent is hyprpolkitagent (source-built).
    ghostty kitty waybar rofi-wayland swaync quickshell
    nautilus nautilus-python ffmpegthumbnailer xarchiver
    wl-clipboard
    grim slurp swappy
    network-manager-applet blueman bluez-tools python3-cairo
    pavucontrol playerctl pamixer pulseaudio-utils
    pipewire-alsa pipewire-utils
    mpv mpv-mpris cava
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

copr_install_isolated "che/nerd-fonts" "nerd-fonts"
copr_install_isolated "ublue-os/packages" "bazaar" "uupd"
copr_install_isolated "errornointernet/packages" "wallust"

rpm-ostree override remove firefox firefox-langpacks || true
