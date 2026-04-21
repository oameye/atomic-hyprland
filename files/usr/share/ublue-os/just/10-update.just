# vim: set ft=make :

# Overrides ublue-os-just's shipped 10-update.just. Upstream still gates
# `ujust update` on `ublue-update.timer`, but this image uses uupd (the Go
# successor) whose unit is `uupd.timer`. Without this override `ujust update`
# reverts to the inline rpm-ostree+flatpak+distrobox fallback -- missing brew
# and uupd's update-inhibitor checks. Invoke the uupd CLI directly (not
# `uupd-manual.service`) so progress streams to the terminal.

alias upgrade := update

# Update rpm-ostree, flatpaks, distroboxes, and brew via uupd.
update:
    sudo /usr/bin/uupd --hw-check=false

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
    if systemctl -q is-enabled ublue-update.timer; then
      CURRENT_STATE="Enabled"
    elif systemctl -q is-enabled rpm-ostreed-automatic.timer; then
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
      if systemctl is-enabled ublue-update.timer 2> /dev/null | grep -q not-found; then
        sudo systemctl enable --now flatpak-system-update.timer rpm-ostreed-automatic.timer
        systemctl enable --now --user flatpak-user-update.timer
      else
        sudo systemctl enable ublue-update.timer
        sudo systemctl disable --now flatpak-system-update.timer rpm-ostreed-automatic.timer
        systemctl disable --now --user flatpak-user-update.timer
      fi
    elif [ "${OPTION,,}" == "disable" ]; then
      if systemctl is-enabled ublue-update.timer 2> /dev/null | grep -q not-found; then
        sudo systemctl disable --now flatpak-system-update.timer rpm-ostreed-automatic.timer
        systemctl disable --now --user flatpak-user-update.timer
      else
        sudo systemctl disable ublue-update.timer
      fi
    fi
