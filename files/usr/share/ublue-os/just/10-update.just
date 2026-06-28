# vim: set ft=make :

# Overrides ublue-os-just's shipped 10-update.just. Upstream's `update` starts
# uupd.service (output goes to the journal, terminal shows nothing) when the
# timer is enabled. We instead run uupd directly with --log-level=debug so manual
# `ujust update` streams per-command output live. uupd handles bootc/rpm-ostree,
# flatpak, distrobox, and brew, so there's no update logic to reimplement here.
# Because this file shares a path with upstream's, it fully shadows it, so the
# other recipes (changelogs, update-firmware, toggle-updates) are kept too.

alias upgrade := update

# Update bootc/rpm-ostree, flatpaks, distroboxes, and brew via uupd with output.
update:
    sudo uupd --log-level=debug

alias changelog := changelogs

# Show the changelog
changelogs:
    rpm-ostree db diff --changelogs

# Update device firmware
[no-exit-message]
update-firmware:
    fwupdmgr refresh --force
    fwupdmgr get-updates
    fwupdmgr update

alias auto-update := toggle-updates

# Turn automatic updates on or off
toggle-updates ACTION="prompt":
    #!/usr/bin/bash
    source /usr/lib/ujust/ujust.sh
    CURRENT_STATE="Disabled"
    if systemctl -q is-enabled uupd.timer; then
      CURRENT_STATE="Enabled"
    fi
    OPTION={{ ACTION }}
    if [ "$OPTION" == "prompt" ]; then
      echo "Automatic updates are currently: ${bold}${CURRENT_STATE}${normal}"
      echo "Enable or Disable automatic updates?"
      OPTION=$(ugum choose Enable Disable)
    elif [ "$OPTION" == "help" ]; then
      echo "Usage: ujust toggle-updates <option>"
      echo "  <option>: Specify the quick option - 'enable' or 'disable'"
      echo "  Use 'enable' to Enable automatic updates."
      echo "  Use 'disable' to Disable automatic updates."
      exit 0
    fi
    if [ "${OPTION,,}" == "enable" ]; then
      sudo systemctl enable --now uupd.timer
    elif [ "${OPTION,,}" == "disable" ]; then
      sudo systemctl disable --now uupd.timer
    fi
