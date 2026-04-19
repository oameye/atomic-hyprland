# atomic-hyprland

A personal Fedora Atomic image based on [Universal Blue `base-main`](https://github.com/ublue-os/main), shipping Hyprland.

See [`DESIGN.md`](./DESIGN.md) for the full design.

## Rebase

```sh
sudo bootc switch ghcr.io/oameye/atomic-hyprland:43
systemctl reboot
```

(Older `rpm-ostree rebase ostree-unverified-registry:ghcr.io/oameye/atomic-hyprland:43` still works on systems that predate `bootc switch`.)

## First boot

A minimal fallback Hyprland config is shipped via `/etc/skel` so SUPER+Return opens a terminal (ghostty), SUPER+D opens rofi, SUPER+M exits, etc. You can work on the system from the moment you log in — no installer needed to unlock the keybinds.

## Install the rice (optional)

We recommend [`LinuxBeginnings/Hyprland-Dots`](https://github.com/LinuxBeginnings/Hyprland-Dots) — a **dotfiles-only** repo that is safe for Fedora Atomic (no `dnf install` calls; it only writes configs into `~/.config`). The related `LinuxBeginnings/Fedora-Hyprland` *installer* is **NOT** compatible with Atomic because it uses `sudo dnf install`; our image has the packages baked in already.

```sh
git clone --depth 1 https://github.com/LinuxBeginnings/Hyprland-Dots ~/Hyprland-Dots
cd ~/Hyprland-Dots
./copy.sh
```

### Switch the default terminal to ghostty

Hyprland-Dots defaults `$term` to `kitty`. After running `copy.sh`, edit `~/.config/hypr/UserConfigs/01-UserDefaults.conf`:

```
$term = ghostty
```

Reload Hyprland (`hyprctl reload`) or log out/in. Both `kitty` and `ghostty` are installed — kitty stays available because Hyprland-Dots' theme switcher references it, but ghostty becomes your Super+Return terminal.

## Rollback

```sh
sudo bootc rollback && systemctl reboot
```

(Older equivalent: `rpm-ostree rollback`.)

## Local development

This repo uses a `Justfile` for local build tasks:

```sh
just build            # build the image locally with podman
just lint             # shellcheck on all .sh files
just format           # shfmt on all .sh files
just check            # verify Justfile syntax
just clean            # remove local build artifacts
```
