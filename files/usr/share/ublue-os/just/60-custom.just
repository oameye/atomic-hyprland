# atomic-hyprland custom ujust recipes.
# Loaded by ublue-os-just's /usr/share/ublue-os/justfile via `import "/usr/share/ublue-os/just/*.just"`.

# Rsync the shipped skel (Hyprland-Dots + our overrides) into $HOME.
# Pass overwrite=1 to clobber existing files, or leave default to only copy files that don't yet exist.
# Example:
#   ujust sync-skel-config              # safe -- skips files that exist
#   ujust sync-skel-config overwrite=1  # overwrite everything from skel
sync-skel-config overwrite="0":
    #!/usr/bin/env bash
    set -eu
    if [ "{{overwrite}}" = "1" ]; then
        echo "Overwriting ~/.config and related dotfiles from /etc/skel ..."
        rsync -av /etc/skel/ "$HOME/"
    else
        echo "Syncing /etc/skel into \$HOME (skipping files that already exist) ..."
        rsync -av --ignore-existing /etc/skel/ "$HOME/"
    fi
    echo
    echo "Done. Run 'hyprctl reload' or log out/in to apply."
