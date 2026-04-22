#!/usr/bin/env bash
set -euo pipefail

PACKAGES=(
	# Greeter — omarchy ships a Qt Quick SDDM theme. Needs qtdeclarative (QtQuick)
	# and qtsvg (for the logo.svg).
	sddm
	qt6-qtsvg qt6-qtdeclarative

	# Desktop — matches the omarchy expected runtime.
	# walker (launcher) + elephant (walker data provider) are source-built;
	# ghostty is installed from scottames/ghostty COPR (see below).
	waybar mako
	swaybg fcitx5 fcitx5-gtk fcitx5-qt
	gnome-calculator
	nautilus nautilus-python ffmpegthumbnailer xarchiver
	tmux imv neovim
	wl-clipboard
	grim slurp gpu-screen-recorder
	# ffmpeg-free + v4l-utils for omarchy-cmd-screenrecord (preview/trim + webcam).
	ffmpeg-free v4l-utils
	network-manager-applet iwd blueman bluez-tools python3-cairo
	# eduVPN client (upstream RPM repo, configured in repos.sh).
	eduvpn-client
	# pamixer for waybar audio-module right-click mute toggle (omarchy config).
	playerctl pulseaudio-utils pamixer
	pipewire-alsa pipewire-utils
	mpv mpv-mpris
	# power-profiles-daemon ships powerprofilesctl, which omarchy scripts
	# call (and which build.sh patches the shebang of to dodge mise's python).
	power-profiles-daemon
	# Printing (omarchy config/hardware/printer.sh) + mDNS discovery
	cups cups-browsed avahi nss-mdns
	# AMD Vulkan (gaming)
	mesa-vulkan-drivers
	# Plymouth boot splash (omarchy ships its own theme)
	plymouth plymouth-plugin-label plymouth-plugin-script
	xdg-desktop-portal-gtk polkit
	brightnessctl
	gtk-murrine-engine
	gvfs gvfs-mtp gvfs-smb
	xdg-user-dirs xdg-utils libnotify inxi
	dbus-tools bc jq nano rsync unzip wget2
	python3-requests python3-pyquery python3-pip
	btop fastfetch
	gnome-keyring libsecret

	# Developer tooling
	code
	make gcc-c++ libstdc++-devel sqlite-devel

	# Containers
	podman-compose podman-tui podman-machine flatpak-builder

	# ROCm (AMD GPU compute)
	rocm-hip rocm-opencl rocm-smi

	# Fonts and theming — JetBrainsMono Nerd Font is source-installed from the
	# ryanoasis/nerd-fonts release in source-builds.sh (Fedora has no Nerd variant
	# and che/nerd-fonts only ships symbols-only).
	fontawesome-fonts-all
	google-noto-emoji-fonts google-noto-color-emoji-fonts google-noto-sans-cjk-fonts
	rsms-inter-fonts
	liberation-fonts jetbrains-mono-fonts
	adobe-source-code-pro-fonts fira-code-fonts google-droid-sans-fonts
	adwaita-icon-theme papirus-icon-theme yaru-icon-theme
)

dnf5 -y install --setopt=install_weak_deps=False "${PACKAGES[@]}"

dnf5 -y install --setopt=install_weak_deps=False --enablerepo=docker-ce-stable \
	docker-ce docker-ce-cli docker-compose-plugin docker-buildx-plugin containerd.io

# tte (terminaltexteffects) — Python 3 CLI used by omarchy-launch-screensaver.
# Not packaged for Fedora; install from PyPI system-wide into /usr. Because we
# own the distribution we can safely use --break-system-packages here.
pip3 install --prefix=/usr --break-system-packages --no-cache-dir \
	terminaltexteffects

copr_install_isolated "ublue-os/packages" "bazaar" "uupd"
copr_install_isolated "erikreider/swayosd" "swayosd"
# ghostty: recommended by upstream ghostty.org install docs.
copr_install_isolated "scottames/ghostty" "ghostty"

rpm-ostree override remove firefox firefox-langpacks || true
