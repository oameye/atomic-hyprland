#!/usr/bin/env bash
set -euo pipefail

DIR="$(dirname "$0")"

# ── Pinned refs — bump these in PRs to upgrade ───────────────────────
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
HYPRPICKER_TAG="v0.4.6"
HYPRSUNSET_TAG="v0.3.3"
XDP_HYPRLAND_TAG="v1.3.11"
HYPR_QT_SUPPORT_TAG="v0.1.0"
HYPR_POLKITAGENT_TAG="v0.1.3"

OMARCHY_REF="v3.5.1"

SATTY_TAG="v0.20.1"
HYPRSHOT_TAG="1.3.0"
CLIPHIST_TAG="v0.7.0"
UWSM_TAG="v0.26.4"
XDG_TERMINAL_EXEC_TAG="v0.12.0"
WALKER_TAG="v2.16.0"
ELEPHANT_TAG="v2.21.0"
WIREMIX_TAG="v0.10.0"
BLUETUI_TAG="v0.8.1"
IMPALA_TAG="v0.7.4"
GUM_TAG="v0.17.0"
STARSHIP_TAG="v1.25.0"

# ── Sub-scripts ──────────────────────────────────────────────────────
source "${DIR}/repos.sh"
source "${DIR}/packages.sh"
source "${DIR}/source-builds.sh"
source "${DIR}/desktop.sh"

# ── Version metadata ─────────────────────────────────────────────────
install -d /usr/share/atomic-hyprland
cat > /usr/share/atomic-hyprland/versions.env <<EOF
OMARCHY_REF=${OMARCHY_REF}
OMARCHY_COMMIT=${OMARCHY_COMMIT}
HYPRLAND_TAG=${HYPRLAND_TAG}
UWSM_TAG=${UWSM_TAG}
XDG_TERMINAL_EXEC_TAG=${XDG_TERMINAL_EXEC_TAG}
EOF

# ── Flathub ──────────────────────────────────────────────────────────
flatpak remote-add --if-not-exists --system flathub \
    https://dl.flathub.org/repo/flathub.flatpakrepo

# Chromium Flatpak overrides — grant filesystem access to the standard
# chromium config paths so the /usr/bin/chromium shim's --user-data-dir
# redirection actually works and omarchy's ~/.config/chromium-flags.conf
# gets picked up by the Flatpak launcher. Override files land under
# /var/lib/flatpak/overrides/ and are in place before the preinstall
# service ever installs the Flatpak on first boot.
flatpak override --system \
    --filesystem=xdg-config/chromium \
    --filesystem=xdg-config/chromium-flags.conf \
    org.chromium.Chromium

# ── Systemd units ────────────────────────────────────────────────────
systemctl enable sddm.service
systemctl enable docker.socket
systemctl enable podman.socket
systemctl enable flatpak-system-update.timer
systemctl enable podman-auto-update.timer
systemctl --global enable flatpak-user-update.timer
systemctl --global enable podman-auto-update.timer
systemctl --global enable atomic-hyprland-detect-kb-layout.service
systemctl enable atomic-hyprland-dx-groups.service
systemctl enable atomic-hyprland-sddm-autologin.service
systemctl enable flatpak-preinstall.service
systemctl enable uupd.timer

# Printing + mDNS discovery (omarchy install/config/hardware/printer.sh).
systemctl enable cups.service
systemctl enable cups-browsed.service
systemctl enable avahi-daemon.service

# Bluetooth on by default (omarchy install/config/hardware/bluetooth.sh).
systemctl enable bluetooth.service

# ── Ported omarchy install/config tweaks ─────────────────────────────
# These edit distro-shipped files that we can't replace wholesale via an
# overlay; sed-patching in place matches how omarchy's installer applies
# them on Arch.

# faillock: 10 retries before lockout (omarchy install/config/increase-sudo-tries.sh).
sed -i 's/^# *deny = .*/deny = 10/' /etc/security/faillock.conf

# PAM faillock tuning (omarchy install/config/increase-lockout-limit.sh).
sed -i 's|^\(auth\s\+required\s\+pam_faillock.so\)\s\+preauth.*$|\1 preauth silent deny=10 unlock_time=120|' \
    /etc/pam.d/system-auth
sed -i 's|^\(auth\s\+\[default=die\]\s\+pam_faillock.so\)\s\+authfail.*$|\1 authfail deny=10 unlock_time=120|' \
    /etc/pam.d/system-auth
# sddm-autologin shouldn't trigger faillock on every boot (sees "no password"
# as a failure). Drop the preauth line and inject an authsucc after the
# pam_permit line so the lockout counter resets on successful boot.
if [[ -f /etc/pam.d/sddm-autologin ]]; then
    sed -i '/pam_faillock\.so preauth/d' /etc/pam.d/sddm-autologin
    sed -i '/auth.*pam_permit\.so/a auth        required    pam_faillock.so authsucc' \
        /etc/pam.d/sddm-autologin
fi

# Physical power button → ignore (omarchy binds Super+Escape to the power
# menu; ignore-power-button.sh). Prevents accidental host shutdowns.
install -d /usr/lib/systemd/logind.conf.d
cat > /usr/lib/systemd/logind.conf.d/atomic-hyprland-power.conf <<'EOF'
[Login]
HandlePowerKey=ignore
EOF

# nsswitch: mDNS resolution for .local via nss-mdns (omarchy printer.sh).
sed -i 's/^hosts:.*/hosts: mymachines mdns_minimal [NOTFOUND=return] resolve files myhostname dns/' \
    /etc/nsswitch.conf

# cups-browsed: auto-add remote network printers (omarchy printer.sh).
if ! grep -q '^CreateRemotePrinters Yes' /etc/cups/cups-browsed.conf; then
    echo 'CreateRemotePrinters Yes' >> /etc/cups/cups-browsed.conf
fi

# powerprofilesctl: force system python over mise's user python
# (omarchy install/config/fix-powerprofilesctl-shebang.sh).
if [[ -f /usr/bin/powerprofilesctl ]]; then
    sed -i '/env python3/ c\#!/bin/python3' /usr/bin/powerprofilesctl
fi

# Plymouth: ship omarchy's theme and set as default. initramfs rebuild is
# handled by rpm-ostree's dracut integration at deploy time.
if [[ -d /etc/skel/.local/share/omarchy/default/plymouth ]]; then
    cp -r /etc/skel/.local/share/omarchy/default/plymouth \
        /usr/share/plymouth/themes/omarchy
    plymouth-set-default-theme omarchy
fi

# system-sleep/unmount-fuse: lazy-unmount gvfsd-fuse mounts before suspend
# and restart gvfs on wake. Without it, suspend can silently fail when the
# user has Nautilus GVFS mounts (MTP phones, SMB shares, etc.) because
# gvfsd-fuse blocks in uninterruptible sleep during the kernel's process
# freeze.
if [[ -f /etc/skel/.local/share/omarchy/default/systemd/system-sleep/unmount-fuse ]]; then
    install -Dm0755 \
        /etc/skel/.local/share/omarchy/default/systemd/system-sleep/unmount-fuse \
        /usr/lib/systemd/system-sleep/unmount-fuse
fi

# Keyring file perms get flattened to 0644/0755 by `COPY files/ /` because
# git only tracks +x bits, not owner-only modes. Restore what GNOME Keyring
# expects. Runs every build; idempotent.
if [[ -d /etc/skel/.local/share/keyrings ]]; then
    chmod 0700 /etc/skel/.local/share/keyrings
    chmod 0600 /etc/skel/.local/share/keyrings/Default_keyring.keyring
    chmod 0644 /etc/skel/.local/share/keyrings/default
fi

# ── dconf system db ──────────────────────────────────────────────────
# Compile the keyfiles under /etc/dconf/db/site.d/ into the `site` binary db
# referenced by /etc/dconf/profile/user. This is how GTK apps pick up the
# dark-mode + Papirus-Dark defaults without per-user gsettings setup.
dconf update

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
