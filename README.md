# atomic-hyprland

> **Personal use only.** This image is built for a single machine: AMD GPU, Fedora 43, no Nvidia support. It is not a general-purpose distribution and is not maintained for anyone else's hardware or workflow. Feel free to fork it as a starting point, but don't expect it to work out of the box for you.

A personal Fedora Atomic image based on [Universal Blue `base-main`](https://github.com/ublue-os/main), shipping Hyprland with [basecamp/omarchy](https://github.com/basecamp/omarchy) baked in.

See [`DESIGN.md`](./DESIGN.md) for the full design.

### Why not [wayblue](https://github.com/wayblueorg/wayblue) or [cjuniorfox/hyprland-atomic](https://github.com/cjuniorfox/hyprland-atomic)?

Both are the obvious-looking prior art (Fedora Atomic + Hyprland). Wayblue installs the hyprwm stack from the `solopasha/hyprland` COPR; cjuniorfox defaults to Fedora's `hyprland` package and optionally falls back to the same `solopasha/hyprland` COPR. Both sources consistently lag behind upstream Hyprland releases. This image source-builds the whole hyprwm ecosystem from pinned git tags ([`source-builds.sh`](./build_files/source-builds.sh)) so it can track current upstream.

## Rebase

```sh
sudo bootc switch ghcr.io/oameye/atomic-hyprland:43
systemctl reboot
```

(Older `rpm-ostree rebase ostree-unverified-registry:ghcr.io/oameye/atomic-hyprland:43` still works on systems that predate `bootc switch`.)

## First boot

The full Omarchy port is shipped in `/etc/skel`. **New user accounts** get it automatically on first login.

**Existing accounts** (if you rebased in, your `$HOME` pre-exists) — sync the skel into your home once.

> **First-time on this image: use `overwrite=1`.** If you've already logged into Hyprland even once, the compositor auto-generated placeholder files (`~/.config/hypr/hyprland.conf` etc.) to let the session start. Those placeholders will **block** a normal `ujust sync-skel-config` (which is `--ignore-existing` for safety). Force the overwrite:
>
> ```sh
> ujust sync-skel-config overwrite=1
> hyprctl reload    # or log out/in
> ```
>
> After this first sync, use the default (`ujust sync-skel-config`, no `overwrite=1`) for routine runs — it will preserve any customizations you've made. `overwrite=1` is the stronger refresh mode: on the first forced sync it refreshes the managed skel subtrees, and on later runs it also prunes files that earlier overwrite runs synced but upstream has since removed.

The default terminal is `ghostty` (omarchy's `xdg-terminals.list` is patched to prefer it over upstream's Alacritty default; all three of alacritty/kitty/ghostty are first-class in omarchy's theme system), the default file manager is `nautilus`, and the default browser is Zen Browser (Flatpak, preinstalled).

### Why isn't this step automatic?

`/etc/skel` is a Linux convention, not an atomic-hyprland invention: it only populates `$HOME` when a user account is first created (`useradd` copies from it). Rebasing an image never re-triggers that, so an account that already exists from a previous deployment bypasses skel completely. This is a property of every Linux system, not a bug.

We deliberately did **not** add an automatic first-login sync because:
1. It races with the compositor startup — a user systemd oneshot can fire after Hyprland has already read `~/.config/hypr/`, leaving a half-synced session.
2. On subsequent image updates (including when this repo bumps the pinned Omarchy ref) we don't want to silently overwrite any customizations you may have made. Keeping it explicit is the consent boundary.

One manual `ujust sync-skel-config` after the first rebase is the price for that simplicity.

### Picking up upstream updates

`ujust sync-skel-config` by default **skips files that already exist**, so running it repeatedly is safe but a no-op past the first run. To pull in new Omarchy configs after upstream has evolved:

```sh
ujust overwrite=1 sync-skel-config
```

(The variable override must come *before* the recipe name — that's how `just` parses its CLI.) This replaces the managed files with the new skel. On the first forced sync it refreshes the managed skel subtrees, and on later runs it also prunes files that older overwrite runs had synced but upstream no longer ships. Commit your `~/.config` to git first if you want a recovery path.

## Updates

- `rpm-ostree upgrade` (or `ujust update`) pulls new images nightly via the inherited uBlue auto-update timers.
- Omarchy is pinned in `build_files/build.sh`; upgrades happen when this repo intentionally bumps `OMARCHY_REF`.
- The shipped image records the resolved Omarchy commit in `/usr/share/atomic-hyprland/versions.env`.
- After reboot, `ujust overwrite=1 sync-skel-config` if you want the new upstream configs to replace yours.

## Rollback

```sh
sudo bootc rollback && systemctl reboot
```

## Optional: enable "bling" shell aliases

`bling` is an opt-in shell init shipped at `/usr/share/ublue-os/bling/bling.sh` (borrowed from Bluefin). It auto-wires **brew-installed** CLI tools into aliases/hooks — `eza` → `ls`/`ll`/`l.`, `bat` → `cat`, `ug` → `grep`, and `starship`/`zoxide`/`mise`/`direnv` init when present. Does nothing if those tools aren't installed. Source it from your shell rc:

```sh
# ~/.bashrc or ~/.zshrc
[ -f /usr/share/ublue-os/bling/bling.sh ] && . /usr/share/ublue-os/bling/bling.sh
```

For fish: `source /usr/share/ublue-os/bling/bling.fish`.

Install the underlying tools via brew when you want them: `brew install eza bat ripgrep ugrep starship zoxide direnv mise`.

## Local development

```sh
just build            # build the image locally with podman
just lint             # shellcheck on all .sh files
just format           # shfmt on all .sh files
just check            # verify Justfile syntax
just clean            # remove local build artifacts
```
