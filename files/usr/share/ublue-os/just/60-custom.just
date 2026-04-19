# atomic-hyprland custom ujust recipes.
# Loaded by ublue-os-just's /usr/share/ublue-os/justfile via `import "/usr/share/ublue-os/just/*.just"`.

# Rsync the shipped skel (Hyprland-Dots + our overrides) into $HOME.
# Pass overwrite=1 to replace managed files from the shipped skel and prune
# files that previous overwrite runs synced but upstream has since removed.
# Leave the default to only copy files that don't yet exist.
# Example:
#   ujust sync-skel-config              # safe -- skips files that exist
#   ujust sync-skel-config overwrite=1  # replace managed files from skel
overwrite := "0"

sync-skel-config:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ "{{overwrite}}" = "1" ]; then
        state_dir="$HOME/.local/state/atomic-hyprland"
        manifest_file="${state_dir}/skel-manifest"
        new_manifest="$(mktemp)"
        trap 'rm -f "$new_manifest"' EXIT

        install -d "$state_dir"
        find /etc/skel -mindepth 1 ! -type d -printf '%P\n' | LC_ALL=C sort > "$new_manifest"

        if [ -f "$manifest_file" ]; then
            while IFS= read -r relpath; do
                [ -n "$relpath" ] || continue
                target="$HOME/$relpath"
                rm -f "$target"

                parent="$(dirname "$target")"
                while [ "$parent" != "$HOME" ]; do
                    rmdir "$parent" 2>/dev/null || break
                    parent="$(dirname "$parent")"
                done
            done < <(comm -23 "$manifest_file" "$new_manifest")
        else
            # First overwrite after rebasing: refresh each managed skel subtree
            # so files that disappeared upstream do not linger in $HOME.
            while IFS= read -r relroot; do
                [ -n "$relroot" ] || continue
                rm -rf "$HOME/$relroot"
            done < <(
                while IFS= read -r entry; do
                    [ -n "$entry" ] || continue
                    if [ -d "/etc/skel/$entry" ]; then
                        find "/etc/skel/$entry" -mindepth 1 -maxdepth 1 -printf '%P\n' \
                            | sed "s|^|${entry}/|"
                    else
                        printf '%s\n' "$entry"
                    fi
                done < <(find /etc/skel -mindepth 1 -maxdepth 1 -printf '%P\n' | LC_ALL=C sort)
            )
        fi

        echo "Replacing managed dotfiles from /etc/skel and pruning removed upstream files ..."
        rsync -av /etc/skel/ "$HOME/"
        cp "$new_manifest" "$manifest_file"
    else
        echo "Syncing /etc/skel into \$HOME (skipping files that already exist) ..."
        rsync -av --ignore-existing /etc/skel/ "$HOME/"
    fi
    echo
    echo "Done. Run 'hyprctl reload' or log out/in to apply."
