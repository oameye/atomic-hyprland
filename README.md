# atomic-hyprland

A personal Fedora Atomic image based on [Universal Blue `base-main`](https://github.com/ublue-os/main), shipping Hyprland + HyDE.

See [`DESIGN.md`](./DESIGN.md) for the full design.

## Rebase

```sh
sudo bootc switch ghcr.io/oameye/atomic-hyprland:43
systemctl reboot
```

(Older `rpm-ostree rebase ostree-unverified-registry:ghcr.io/oameye/atomic-hyprland:43` still works on systems that predate `bootc switch`.)

## After first boot

Run HyDE's installer once:

```sh
bash <(curl -s https://raw.githubusercontent.com/HyDE-Project/HyDE/master/Scripts/install.sh)
```

For ghostty theming, also clone [`HyDE-Project/terminal-emulators`](https://github.com/HyDE-Project/terminal-emulators) and copy its `ghostty/` directory into `~/.config/`.

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
