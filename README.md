# atomic-hyprland

A personal Fedora Atomic image based on [Universal Blue `base-main`](https://github.com/ublue-os/main), shipping Hyprland with [LinuxBeginnings/Hyprland-Dots](https://github.com/LinuxBeginnings/Hyprland-Dots) baked in.

See [`DESIGN.md`](./DESIGN.md) for the full design.

## Rebase

```sh
sudo bootc switch ghcr.io/oameye/atomic-hyprland:43
systemctl reboot
```

(Older `rpm-ostree rebase ostree-unverified-registry:ghcr.io/oameye/atomic-hyprland:43` still works on systems that predate `bootc switch`.)

## First boot

The full LinuxBeginnings Hyprland-Dots rice is shipped in `/etc/skel`. New user accounts get it automatically on first login.

**Existing accounts** (if you rebased from Aurora, your `$HOME` pre-exists) — sync the skel into your home once:

```sh
ujust sync-skel-config
```

Log out/in (or `hyprctl reload`). The default terminal is already `ghostty` (we patch Hyprland-Dots' `$term` at build time).

### Overwriting existing configs

`ujust sync-skel-config` skips files that already exist in `$HOME`. To overwrite (e.g., after rebase you want the newest upstream configs to stomp your local edits):

```sh
ujust sync-skel-config overwrite=1
```

Commit your own `~/.config` to git before doing this.

## Updates

- `rpm-ostree upgrade` (or `ujust update`) pulls new images nightly via the inherited uBlue auto-update timers.
- Every weekly image build pulls the **latest** LinuxBeginnings/Hyprland-Dots master — no manual dots update step.
- After reboot, `ujust sync-skel-config overwrite=1` if you want the new upstream configs to replace yours.

## Rollback

```sh
sudo bootc rollback && systemctl reboot
```

## Local development

```sh
just build            # build the image locally with podman
just lint             # shellcheck on all .sh files
just format           # shfmt on all .sh files
just check            # verify Justfile syntax
just clean            # remove local build artifacts
```
