#!/usr/bin/env bash
# Layer 2 of 2 — packages, desktop, systemd, cleanup.
# Repos and source-built binaries are already in the image from source-builds.sh.
set -euo pipefail

DIR="$(dirname "$0")"

# ── Pinned refs — bump these in PRs to upgrade ───────────────────────
SDDM_HYPRLAND_TAG="v0.48.0"
SDDM_ASTRONAUT_COMMIT="d73842c"
SDDM_ASTRONAUT_VARIANT="astronaut"

# Enable a COPR, immediately disable it, then install packages from it via
# --enablerepo so no .repo file survives in the final image.
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

# ── Layer 2 steps ────────────────────────────────────────────────────
source "${DIR}/packages.sh"
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
