#!/usr/bin/env bash
set -euo pipefail

RELEASE="$(rpm -E %fedora)"
DIR="$(dirname "$0")"

# ── Pinned refs — bump these in PRs to upgrade ───────────────────────
SDDM_HYPRLAND_TAG="v0.48.0"
SDDM_ASTRONAUT_COMMIT="d73842c"
SDDM_ASTRONAUT_VARIANT="astronaut"

# Build order: hyprwayland-scanner → hyprutils → hyprlang → hyprcursor
#   → hyprgraphics → aquamarine → hyprwire → hyprland
#   → hyprtoolkit → hyprland-guiutils
#   → satellite tools → Qt6 components
HYPRWAYLAND_SCANNER_TAG="v0.4.5"
HYPRUTILS_TAG="v0.12.0"
HYPRLANG_TAG="v0.6.8"
HYPRCURSOR_TAG="v0.1.13"
HYPRGRAPHICS_TAG="v0.5.1"
AQUAMARINE_TAG="v0.10.0"
HYPRWIRE_TAG="v0.3.0"
HYPRLAND_PROTOCOLS_TAG="v0.7.0"
GLAZE_TAG="v7.1.1"
HYPRLAND_TAG="v0.54.3"
HYPRTOOLKIT_TAG="v0.5.3"
HYPR_GUIUTILS_TAG="v0.2.1"
HYPRLOCK_TAG="v0.9.5"
HYPRIDLE_TAG="v0.1.7"
HYPRPAPER_TAG="v0.8.3"
HYPRPICKER_TAG="v0.4.6"
HYPRSUNSET_TAG="v0.3.3"
XDP_HYPRLAND_TAG="v1.3.11"
HYPR_QT_SUPPORT_TAG="v0.1.0"
HYPR_POLKITAGENT_TAG="v0.1.3"

AWWW_TAG="v0.12.0"
SWWW_TAG="v0.11.2"
SATTY_TAG="v0.20.1"
HYPRSHOT_TAG="1.3.0"
CLIPHIST_TAG="v0.7.0"
NWGLOOK_TAG="v1.0.6"
UWSM_TAG="v0.26.4"

# ── Sub-scripts ──────────────────────────────────────────────────────
# shellcheck source=repos.sh
source "${DIR}/repos.sh"
# shellcheck source=packages.sh
source "${DIR}/packages.sh"
# shellcheck source=source-builds.sh
source "${DIR}/source-builds.sh"
# shellcheck source=desktop.sh
source "${DIR}/desktop.sh"

# ── Flathub ──────────────────────────────────────────────────────────
flatpak remote-add --if-not-exists --system flathub \
    https://dl.flathub.org/repo/flathub.flatpakrepo

# ── Systemd units ────────────────────────────────────────────────────
systemctl enable sddm.service
systemctl enable docker.socket
systemctl enable podman.socket
systemctl enable flatpak-system-update.timer
systemctl enable podman-auto-update.timer
systemctl --global enable flatpak-user-update.timer
systemctl --global enable podman-auto-update.timer
systemctl enable atomic-hyprland-dx-groups.service
systemctl enable flatpak-preinstall.service
systemctl enable uupd.timer

# ── Cleanup ───────────────────────────────────────────────────────────
dnf5 clean all
rm -rf \
    /var/cache/dnf \
    /var/cache/libdnf5 \
    /var/lib/dnf \
    /var/lib/blueman \
    /tmp/* \
    /var/tmp/*

echo "Build complete."
