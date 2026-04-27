#!/usr/bin/env bash
# Shared expected artifacts for build-time enablement and post-build
# verification. Keep these arrays authoritative when adding/removing shipped
# executables or enabled units.
#
# shellcheck disable=SC2034
# Reason: this file is a sourced data module; the arrays are consumed by other
# scripts, not within this file itself.

SOURCE_BUILT_HYPRWM_EXECUTABLES=(
	/usr/bin/Hyprland
	/usr/bin/hyprctl
	/usr/bin/hyprlock
	/usr/bin/hypridle
	/usr/bin/hyprpicker
	/usr/bin/hyprsunset
	# Portals and polkit agents install to libexec by FDO convention.
	/usr/libexec/xdg-desktop-portal-hyprland
	/usr/libexec/hyprpolkitagent
)

SOURCE_BUILT_AUX_EXECUTABLES=(
	/usr/bin/walker
	/usr/bin/wiremix
	/usr/bin/hyprland-preview-share-picker
	/usr/bin/cliphist
	/usr/bin/elephant
	/usr/bin/gum
	/usr/bin/hyprshot
	/usr/bin/uwsm
	/usr/bin/xdg-terminal-exec
)

PACKAGED_DESKTOP_EXECUTABLES=(
	/usr/bin/sddm
	/usr/bin/waybar
	/usr/bin/mako
	/usr/bin/ghostty
	/usr/bin/code
	/usr/bin/bazaar
	/usr/bin/uupd
	/usr/bin/starship
	/usr/bin/impala
	/usr/bin/bluetui
	/usr/bin/satty
	# swayosd COPR ships swayosd-server + swayosd-client, no bare 'swayosd'.
	/usr/bin/swayosd-server
	/usr/bin/swayosd-client
	/usr/bin/docker
)

SYSTEM_UNITS=(
	sddm.service
	docker.socket
	podman.socket
	flatpak-system-update.timer
	podman-auto-update.timer
	atomic-hyprland-dx-groups.service
	atomic-hyprland-sddm-autologin.service
	flatpak-preinstall.service
	uupd.timer
	cups.service
	cups-browsed.service
	avahi-daemon.service
	bluetooth.service
)

GLOBAL_UNITS=(
	flatpak-user-update.timer
	podman-auto-update.timer
	atomic-hyprland-detect-kb-layout.service
	elephant.service
)
