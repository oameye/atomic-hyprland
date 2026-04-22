#!/usr/bin/env bash
# Layer 2 of 2 — packages, desktop, systemd, cleanup.
# Repos and source-built binaries are already in the image from source-builds.sh.
set -euo pipefail

DIR="$(dirname "$0")"

# ── Pinned refs used in layer 2 ──────────────────────────────────────
OMARCHY_REF="v3.5.1"
HYPRLAND_TAG="v0.54.3"
UWSM_TAG="v0.26.4"
XDG_TERMINAL_EXEC_TAG="v0.12.0"

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

# Chromium theming uses the supported Linux managed-policy path under
# /etc/chromium/policies/managed. Make it user-writable like upstream
# omarchy so theme switches can update BrowserThemeColor without sudo.
install -d -m 0777 /etc/chromium/policies/managed

# Baseline policy so the first chromium launch (before any omarchy-theme-set
# invocation) already renders with the tokyo-night accent + follows the
# system colour scheme. Background RGB #1a1b26 → "#1a1b26"; later theme
# switches rewrite this file via omarchy-theme-set-browser.
cat > /etc/chromium/policies/managed/color.json <<'EOF'
{"BrowserThemeColor": "#1a1b26", "BrowserColorScheme": "device"}
EOF
chmod 0666 /etc/chromium/policies/managed/color.json

# Chromium Flatpak overrides — grant filesystem access to the standard
# chromium config paths plus the managed-policy directory so the shim's
# --user-data-dir redirection works, ~/.config/chromium-flags.conf gets
# picked up, and Flatpak Chromium can read the host policy file.
# Override files land under /var/lib/flatpak/overrides/ and are in place
# before the preinstall service ever installs the Flatpak on first boot.
flatpak override --system \
    --filesystem=/etc/chromium:ro \
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
systemctl --global enable elephant.service
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

# Prevent password-based SDDM logins from creating an encrypted login keyring
# that conflicts with the passwordless Default_keyring shipped under
# /etc/skel/.local/share/keyrings (omarchy install/login/sddm.sh).
if [[ -f /etc/pam.d/sddm ]]; then
    sed -i '/-auth.*pam_gnome_keyring\.so/d' /etc/pam.d/sddm
    sed -i '/-password.*pam_gnome_keyring\.so/d' /etc/pam.d/sddm
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

# sudo refuses to read sudoers.d entries that are group/world writable, and
# modern versions want 0440. `COPY files/ /` flattens them to 0644 — restore
# the strict mode so the rules actually take effect.
for f in /etc/sudoers.d/passwd-tries /etc/sudoers.d/omarchy-tzupdate; do
    [[ -f $f ]] && chmod 0440 "$f"
done

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

# ── Post-build assertions ─────────────────────────────────────────────
# Runs after cleanup so we verify what actually ships. Exits non-zero on
# any regression, which fails the podman build.
bash "${DIR}/verify.sh"

echo "Build complete."
