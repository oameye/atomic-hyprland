# atomic-hyprland

A personal Fedora Atomic image based on [Universal Blue `base-main`](https://github.com/ublue-os/main), shipping Hyprland + HyDE.

See [`DESIGN.md`](./DESIGN.md) for the full design.

## Rebase

```sh
rpm-ostree rebase ostree-unverified-registry:ghcr.io/oameye/atomic-hyprland:43
systemctl reboot
```

## After first boot

Run HyDE's installer once:

```sh
bash <(curl -s https://raw.githubusercontent.com/HyDE-Project/HyDE/master/Scripts/install.sh)
```

For ghostty theming, also clone [`HyDE-Project/terminal-emulators`](https://github.com/HyDE-Project/terminal-emulators) and copy its `ghostty/` directory into `~/.config/`.

## Rollback

```sh
rpm-ostree rollback && systemctl reboot
```
