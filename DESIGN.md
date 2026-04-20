# Atomic-Hyprland — Design

A personal Fedora Atomic image shipping Hyprland with [basecamp/omarchy](https://github.com/basecamp/omarchy) on top of Universal Blue's `base-main`. Single-user, AMD GPU only.

This file documents intent and invariants. Current values (pinned tags, package list, Fedora version) live in [`build_files/`](./build_files/) and are the source of truth.

## Goals

- Fedora Atomic base with Universal Blue's plumbing (auto-updates, `ujust`, Homebrew).
- First-boot-ready desktop: full rice baked in, no post-install package commands.
- All fast-moving components (Hyprland ecosystem) pinned and source-built; updates are deliberate PRs.
- Minimal surface: `Containerfile` + `build_files/` scripts + static `files/` overlay. No BlueBuild.
- Personal use only — no user-facing CLI wrappers beyond one `ujust` recipe, no welcome flows, no ISO.

## Architecture

| | |
|---|---|
| Base image | `ghcr.io/ublue-os/base-main`, Fedora version pinned in `Containerfile` and CI |
| Image registry | `ghcr.io/<gh-user>/atomic-hyprland`, public GHCR |
| Signing | None — single-user personal threat model |
| Tags | `:<fedora-ver>`, `:latest`, `:<fedora-ver>-<YYYYMMDD>`, `:pr-<N>` |

## Package layering

- **Hyprland ecosystem** — all source-built in `source-builds.sh`. See [Source builds](#source-builds).
- **Session / greeter** — `sddm` + `qt6-qtdeclarative` + `qt6-qtsvg` for omarchy's Qt Quick SDDM theme.
- **Desktop runtime** — packages omarchy expects: waybar, mako, swaybg, swayosd, fcitx5, gnome-calculator, polkit-gnome, nautilus, ghostty (first-class omarchy-themed terminal; xdg-terminals.list is patched to prefer it over upstream's Alacritty default), wl-clipboard, grim/slurp/swappy, audio stack, wallust, mpv, btop, fastfetch, tmux, imv, starship, neovim (LazyVim bootstrapped by `/etc/skel/.config/nvim/init.lua` on first launch; a plugin spec sources `~/.config/omarchy/current/neovim.lua` so the active omarchy theme's colorscheme plugin loads automatically); walker + elephant are source-built.
- **Qt theming** — `qt5ct` + `kvantum-qt5` (Qt5) and `qt6ct` + `qt6-qt5compat` (Qt6) for Qt app theming.
- **Developer tooling** — VS Code (RPM), make, gcc-c++. Everything else (`fd`, `fzf`, `lazygit`, `yazi`, …) via `brew`.
- **Containers** — `podman-compose`, `podman-tui`, `podman-machine`, `flatpak-builder`, Docker CE.
- **GPU compute** — ROCm user-space (`rocm-hip`, `rocm-opencl`, `rocm-smi`) for AMD.
- **Fonts + theming** — Fedora fonts, `nerd-fonts` (from `che/nerd-fonts` COPR, isolated install), `adwaita-icon-theme`, `papirus-icon-theme`, `kvantum`.

### COPR policy

- **Left enabled** — `pgdev/ghostty` Copr (ghostty isn't in Fedora default repos), `pgo/gpu-screen-recorder` Copr (upstream author's own packaging; the `-w portal` recording path used by `omarchy-cmd-screenrecord` needs the native binary, not a Flatpak, so `pkill -f "^gpu-screen-recorder"` matches the process on stop), VS Code, Docker CE (`enabled=0`, used via `--enablerepo`).
- **Isolated** — `che/nerd-fonts`, `ublue-os/packages`, `errornointernet/packages`. Installed via `copr_install_isolated`; no `.repo` file survives in the final image.

## Source builds

The entire Hyprland ecosystem is source-built for exact version control and ABI consistency. All tags are pinned in `build.sh`; upgrading is a one-line PR.

**Core library chain** (each depends on the previous):

`hyprwayland-scanner` → `hyprutils` → `hyprlang` → `hyprcursor` → `hyprgraphics` → `aquamarine`

**Compositor:** `hyprland` — uses `--recurse-submodules` for bundled `udis86`.

**Toolkit:** `hyprtoolkit` → `hyprland-guiutils` (Wayland-native).

**Satellite tools:** `hyprlock`, `hypridle`, `hyprpaper`, `hyprpicker`, `hyprsunset`, `xdg-desktop-portal-hyprland`.

**Qt6 components:** `hyprland-qt-support` (QML style plugin), `hyprpolkitagent` (polkit agent).

**Non-hyprwm tools:**

| Tool | Build | Purpose |
|---|---|---|
| `awww` | Cargo | preferred wallpaper daemon |
| `swww` | Cargo | animated wallpaper fallback |
| `satty` | Cargo + GTK4 | screenshot annotation |
| `hyprshot` | curl (shell script) | screenshot helper |
| `cliphist` | Go | clipboard history |
| `nwg-look` | Go + GTK3 | GTK settings GUI |
| `uwsm` | Python / meson | Wayland session manager |
| `walker` | Go + GTK4 + gtk-layer-shell | application launcher (omarchy default) |
| `elephant` | Go | walker data provider (required for walker ≥ v2) |
| `wiremix` | Cargo | PipeWire audio TUI (Super+Ctrl+A) |
| `bluetui` | Cargo | Bluetooth TUI (Super+Ctrl+B) |
| `impala` | Cargo | Wi-Fi TUI (Super+Ctrl+W) — talks to iwd |

Build-only toolchains (cmake, meson, rust/cargo, golang, Qt6 devel) are removed after all builds complete.

## Desktop environment

`basecamp/omarchy` is cloned unpinned (master) each build and deployed to match upstream's on-disk layout. Upstream expects `$OMARCHY_PATH=~/.local/share/omarchy` with `{default,themes,bin}` underneath — both `config/uwsm/env` and `default/bash/envs` put `$OMARCHY_PATH/bin` first on `PATH`, so matching this layout lets every `omarchy-*` script find its siblings and templates unmodified:

- `config/` → `/etc/skel/.config/` (user dotfiles; sourced by Hyprland, terminals, waybar, etc.)
- `default/` → `/etc/skel/.local/share/omarchy/default/` (hyprland.conf sources `default/hypr/**/*.conf` at runtime; templates in `default/themed/*.tpl` feed the theme renderer)
- `themes/` → `/etc/skel/.local/share/omarchy/themes/` (19 built-in themes)
- `bin/` → `/etc/skel/.local/share/omarchy/bin/` (waybar menu, theme switching, launchers)

Shell + env integration:

- `/etc/skel/.bashrc.d/omarchy.sh` sources `default/bashrc` on interactive login (starship prompt, aliases, `$OMARCHY_PATH`, `$PATH` rewrites).
- `config/uwsm/env` (shipped by omarchy, copied to `/etc/skel/.config/uwsm/env`) sets the same env for the Hyprland graphical session, so `omarchy-launch-*` invoked from waybar / keybinds gets `$OMARCHY_PATH` even without bash in the chain.
- `/etc/skel/.XCompose` is a relative symlink to `default/xcompose` for GTK/X11 compose sequences.

### Initial theme bootstrap

`omarchy-theme-set-templates` renders per-app theme files (`alacritty.toml`, `kitty.conf`, `ghostty.conf`, `waybar.css`, `mako.ini`, `hyprland.conf` theme, `hyprlock.conf`, `swayosd.css`, `walker.css`, `btop.theme`, `keyboard.rgb`, `chromium.theme`, `obsidian.css`, `hyprland-preview-share-picker.css`) from `colors.toml` + `default/themed/*.tpl` via sed substitution of `{{ key }}` / `{{ key_rgb }}` / `{{ key_strip }}` placeholders. Upstream omarchy runs this on every `omarchy-theme-set <name>` invocation; since we don't run omarchy's installer, `desktop.sh` replays the script once at build time (subshell with `HOME=/etc/skel`, `OMARCHY_PATH=/etc/skel/.local/share/omarchy`) to pre-populate `~/.config/omarchy/current/theme/` with a rendered **tokyo-night**. At first login every terminal import (`config-file = ?"~/.config/omarchy/current/theme/ghostty.conf"` etc.) hits a real file, VS Code's `theme/vscode.json` is ready for `omarchy-theme-set-vscode`, and Neovim's `lua/plugins/omarchy-theme.lua` `dofile`s the live `neovim.lua`.

After first login, `omarchy-theme-set <any-theme>` works unmodified: it copies the target theme dir into `current/next-theme/`, re-runs `omarchy-theme-set-templates`, atomic-swaps into `current/theme/`, and fires the restart-* / theme-set-* fan-out (waybar, swayosd, ghostty, mako, btop, VS Code, GNOME settings, keyboard RGB, browser chrome, Obsidian).

### Walker / elephant service

Walker v2 expects a persistent background process with elephant as its data provider. `desktop.sh` ports omarchy's `install/config/walker-elephant.sh`:

- XDG autostart entry at `/etc/skel/.config/autostart/walker.desktop`
- Systemd user drop-in at `/etc/skel/.config/systemd/user/app-walker@autostart.service.d/restart.conf` — restart-on-crash
- Relative symlinks under `/etc/skel/.config/elephant/menus/` pointing at `default/elephant/omarchy_{themes,background_selector}.lua` — populates the "Style → Theme" and "Background" menus

Upstream's pacman `PostTransaction` hook is skipped (rpm-ostree rebuilds pick up walker/elephant updates via image rebase; users restart the session normally).

### GTK / GNOME defaults

Dark-mode + Papirus-Dark + CaskaydiaMono Nerd Font are baked in as a **dconf system db** under `files/etc/dconf/db/site.d/10-omarchy-gtk`. `dconf update` runs at the end of `build.sh` to compile the binary. `/etc/dconf/profile/user` chains `user-db:user` over `system-db:site`, so per-user `gsettings set` still overrides, but the baseline is coherent before any user has logged in. `omarchy-theme-set-gnome` flips these keys at runtime to match each theme.

### Misc system tweaks (ported from `install/config/`)

Pure static overlays under `files/`:

**Static overlays** (`files/`):

| Drop-in | Purpose | Upstream source |
|---|---|---|
| `etc/sysctl.d/90-omarchy-file-watchers.conf` | `fs.inotify.max_user_watches=524288` for LazyVim / VS Code | increase-file-watchers.sh |
| `etc/sysctl.d/99-omarchy-ssh-mtu.conf` | `tcp_mtu_probing=1` for flaky SSH links | ssh-flakiness.sh |
| `etc/systemd/system.conf.d/10-faster-shutdown.conf` | `DefaultTimeoutStopSec=5s` | fast-shutdown.sh |
| `etc/systemd/system/user@.service.d/faster-shutdown.conf` | same cap on user session teardown | same |
| `etc/systemd/system/plocate-updatedb.service.d/ac-only.conf` | `ConditionACPower=true` so indexer doesn't run on battery | plocate-ac-only.sh |
| `etc/sudoers.d/passwd-tries` | `Defaults passwd_tries=10` (applies to hyprlock via faillock too) | increase-sudo-tries.sh |
| `etc/systemd/resolved.conf.d/10-disable-multicast.conf` | `MulticastDNS=no` (avahi owns `.local`) | hardware/printer.sh |
| `etc/modprobe.d/disable-usb-autosuspend.conf` | `options usbcore autosuspend=-1` (no HID dropouts) | hardware/usb-autosuspend.sh |
| `etc/gnupg/dirmngr.conf` | 5 keyserver fallbacks + 4 s quick-timeout | default/gpg/dirmngr.conf |

**In-place sed patches** (`build.sh`, after packages are installed):

| Target | Edit | Upstream source |
|---|---|---|
| `/etc/security/faillock.conf` | `deny=10` | increase-sudo-tries.sh |
| `/etc/pam.d/system-auth` | faillock `deny=10 unlock_time=120` on preauth + authfail lines | increase-lockout-limit.sh |
| `/etc/pam.d/sddm-autologin` | drop preauth faillock, inject `authsucc` after `pam_permit` | same |
| `/etc/systemd/logind.conf` | `HandlePowerKey=ignore` (bound to power menu via Super+Escape instead) | hardware/ignore-power-button.sh |
| `/etc/nsswitch.conf` | `hosts: mymachines mdns_minimal [NOTFOUND=return] …` | hardware/printer.sh |
| `/etc/cups/cups-browsed.conf` | append `CreateRemotePrinters Yes` | same |
| `/usr/bin/powerprofilesctl` | shebang `#!/bin/python3` to dodge mise's python | fix-powerprofilesctl-shebang.sh |

**Plymouth theme**: `build.sh` copies `default/plymouth/` → `/usr/share/plymouth/themes/omarchy/` and runs `plymouth-set-default-theme omarchy`. Initramfs regeneration is handled by rpm-ostree's dracut integration at deploy time (no `-R` flag needed).

**Systemd units enabled** (in addition to the existing sddm/docker/podman/flatpak/uupd lineup): `cups.service`, `cups-browsed.service`, `avahi-daemon.service`, `bluetooth.service`.

**Intentionally skipped**:
- `wifi-powersave-rules.sh`, `powerprofilesctl-rules.sh` — udev rules that bake `$HOME` into `RUN+=`; laptop-only, this image is a desktop.
- `input-group.sh` — covered by `atomic-hyprland-dx-groups.service` for the first interactive user.
- `gpg.sh` — handled above via `files/etc/gnupg/dirmngr.conf` overlay (not user-scoped on reflection).
- `default-keyring.sh` — handled via `files/etc/skel/.local/share/keyrings/` overlay: `Default_keyring.keyring` (0600) + `default` (0644) pointer file inside a 0700 directory. `ctime=0` is hardcoded since nothing reads it meaningfully.
- `detect-keyboard-layout.sh` — ported as a user-scoped first-login helper. `/usr/bin/atomic-hyprland-detect-kb-layout` queries `localectl` for the X11 layout Anaconda wrote during install (Fedora uses `/etc/X11/xorg.conf.d/00-keyboard.conf` rather than Arch's `/etc/vconsole.conf`, and `localectl` abstracts both) and patches `~/.config/hypr/input.conf` if the user hasn't already set a layout. Driven by `atomic-hyprland-detect-kb-layout.service` (user unit at `/usr/lib/systemd/user/`, `systemctl --global enable`-d in `build.sh`) with a `ConditionPathExists=!%h/.local/state/atomic-hyprland/kb-layout-done` tombstone so it runs exactly once per user.
- `git.sh` — genuinely requires user-entered identity (name + email); left for the user to run `git config --global user.{name,email}` once. Omarchy's upstream only automates this because its TUI prompts for it.
- `hardware/` scripts for apple/asus/dell/framework/intel/nvidia/tuxedo/surface/bcm43xx/yt6801/synaptic — unrelated hardware.
- `hardware/network.sh` — partially superseded by our NetworkManager + iwd backend config; upstream also masks `systemd-networkd-wait-online.service` which is Arch-specific.
- `branding.sh` — replayed in `desktop.sh` instead (copies `icon.txt`/`logo.txt` and sets up `~/.config/omarchy/branding/`).
- `migrations/` — only matters between omarchy version upgrades; CI rebuilds from master weekly, so the image always ships latest defaults. `ujust sync-skel-config overwrite=1` refreshes managed subtrees after a rebase.

Mimeapps: omarchy ships no `mimeapps.list`, so `files/etc/skel/.config/mimeapps.list` fills the gap. It mirrors omarchy's upstream `install/config/mimetypes.sh`, adapted for Fedora + Flatpak: URLs/HTML → Zen Browser (Flatpak), mailto → Thunderbird (Flatpak), PDFs → GNOME Papers (Flatpak), images → imv, video/audio → mpv, directories → Nautilus, archives → Xarchiver, text files → nvim. Because `files/` is overlaid before `desktop.sh` copies omarchy's `config/`, and omarchy has no same-path conflict, this static file survives the build intact.

Default Hyprland theme `tokyo-night` is symlinked at `/etc/skel/.config/omarchy/current`. Default monospace font is `CaskaydiaMono Nerd Font` (omarchy upstream uses JetBrainsMono); a recursive sed in `desktop.sh` rewrites every reference in `/etc/skel` and the SDDM theme.

### Bin script audit

Every script under omarchy's `bin/` was audited for pacman/yay/AUR references. Outcomes:

| Category | Scripts | Action |
|---|---|---|
| **Install wrappers** | `omarchy-install-*`, `omarchy-pkg-*`, `omarchy-webapp-*`, `omarchy-tui-*`, `omarchy-windows-*` | Deleted (Install menu stripped) |
| **Pacman-only lifecycle** | `omarchy-refresh-pacman`, `omarchy-channel-set`, `omarchy-update-system-pkgs`, `omarchy-update-aur-pkgs`, `omarchy-update-keyring`, `omarchy-update-orphan-pkgs`, `omarchy-reinstall-pkgs`, `omarchy-version-channel`, `omarchy-version-pkgs` | Deleted (orphaned — Update menu entry bottoms out at `ujust update`; channel switching is meaningless on rpm-ostree-rebuilt images) |
| **Full-file replacements** | `omarchy-update`, `omarchy-update-available`, `omarchy-launch-browser`, `omarchy-theme-set-browser` | Overwritten with Fedora/Flatpak-aware logic |
| **Graceful failure patches** | `omarchy-remove-dev-env`, `omarchy-setup-fido2`, `omarchy-setup-fingerprint` | `pacman -Rns` lines sed-appended with `\|\| true` — scripts still do their real work (udev rules, pam, systemd), only the "uninstall the old Arch package first" step no-ops |
| **Targeted sed patches** | `omarchy-debug`, `omarchy-upload-log` | Package-listing step rewritten from `expac`/`pacman -Q` to `rpm -qa \| sort`; rest of the script unchanged |
| **Dependency-satisfied** | `omarchy-launch-screensaver`, `omarchy-launch-webapp` | `tte` installed via pip for the screensaver; Chromium Flatpak + `/usr/bin/chromium` shim for webapp launches |
| **Safe no-ops** | `omarchy-voxtype-status` | `omarchy-cmd-present voxtype` gate makes it a silent no-op on our image |
| **Works unmodified** | Everything else (`omarchy-theme-*`, `omarchy-launch-*` for installed apps, `omarchy-restart-*`, `omarchy-toggle-*`, `omarchy-cmd-*`, `omarchy-menu` minus Install, `omarchy-font-*`, `omarchy-hook`, etc.) | — |

### Arch → Fedora strip

Rather than sed-patch Arch package names, `desktop.sh` removes the broken paths outright:

- `omarchy-install-*`, `omarchy-pkg-*`, `omarchy-webapp-*`, `omarchy-tui-*`, `omarchy-windows-*` scripts are deleted from skel. Apps are installed via Flatpak / COPR / brew, not pacman / yay.
- The "Install" entry is stripped from the top-level `omarchy-menu` (menu string + case handler).
- `omarchy-update` is replaced with a one-line wrapper around `ujust update`, which handles bootc (`rpm-ostree upgrade`), Flatpak, and brew in one shot.
- `omarchy-launch-browser` is replaced with a direct Zen Browser wrapper (`flatpak run app.zen_browser.zen`). Upstream's lookup goes through `xdg-settings` which doesn't search Flatpak export paths, so a full-file override is cleaner than patching.
- `omarchy-update-available` (waybar's update indicator, 6h poll) is replaced with a Fedora-aware check: `rpm-ostree status --json` for staged bootc deployments + `flatpak remote-ls --updates` for pending Flatpak updates. Upstream's version git-ls-remotes `$OMARCHY_PATH`, which errors out on our `cp -a` (no `.git/`).
- Two bindings are `sed`-deleted from `default/hypr/bindings/utilities.conf`: `omarchy-brightness-display-apple` (Apple-hardware-only helper) and `voxtype record toggle` (AUR-only voice dictation).

### Networking — NetworkManager + iwd backend

NetworkManager is configured to use `iwd` as its Wi-Fi backend via `files/etc/NetworkManager/conf.d/wifi_backend.conf`. The `iwd` package is installed; NetworkManager starts `iwd` on demand over D-Bus (no separate `systemctl enable iwd.service` needed). This way NetworkManager still owns connection profiles (so `nmcli`, `network-manager-applet`, and system integrations keep working) while `impala` talks directly to the same `iwd` daemon and sees the same devices/networks.

### Applying the skel to an existing `$HOME`

`/etc/skel` only populates `$HOME` on new-user creation. A `ujust` recipe handles existing accounts:

```sh
ujust sync-skel-config              # merge — skips files that already exist
ujust sync-skel-config overwrite=1  # replace managed subtrees from the new skel
```

## SDDM greeter

Omarchy ships its own lightweight Qt Quick SDDM theme (`default/sddm/omarchy/`). `desktop.sh` copies it to `/usr/share/sddm/themes/omarchy`. Runtime deps are just `qt6-qtdeclarative` (QtQuick) and `qt6-qtsvg` (for `logo.svg`).

Static config in `files/etc/sddm.conf.d/theme.conf` sets `Current=omarchy`. No separate compositor setup is needed; SDDM uses its default Wayland greeter backend.

### Autologin

`atomic-hyprland-sddm-autologin.service` is a `Before=sddm.service` oneshot that writes `/etc/sddm.conf.d/autologin.conf` on first boot. The helper at `/usr/bin/atomic-hyprland-sddm-autologin` finds the first `UID_MIN..UID_MAX` user (respecting `/etc/login.defs`) and sets `User=<that>` + `Session=hyprland-uwsm` — same format omarchy's installer produces.

`ConditionPathExists=!/etc/sddm.conf.d/autologin.conf` makes the unit a no-op after success. If the unit runs before any user exists (unusual but possible on early-stage image deployments), the helper exits cleanly and the unit retries next boot since the target file still doesn't exist.

## Preinstalled Flatpaks

Firefox is removed (`rpm-ostree override remove`). User-facing desktop apps are shipped via Flatpak so they stay out of the base image and can update independently:

| App | Flatpak ID | Role |
|---|---|---|
| [Zen Browser](https://zen-browser.app/) | `app.zen_browser.zen` | default browser |
| GNOME Papers | `org.gnome.Papers` | PDF viewer (omarchy upstream uses Evince; Papers is the Fedora 41+ successor) |
| Xournal++ | `com.github.xournalpp.xournalpp` | PDF annotation / handwritten notes |
| Thunderbird | `org.mozilla.Thunderbird` | mailto handler |
| Signal Desktop | `org.signal.Signal` | Super+Alt+G binding target |
| Obsidian | `md.obsidian.Obsidian` | Super+Alt+O binding target |
| Chromium | `org.chromium.Chromium` | `omarchy-launch-webapp` (PWAs) + `omarchy-theme-set-browser` target |

A small `/usr/bin/chromium` shim under `files/usr/bin/` `exec`s the Flatpak, so `omarchy-cmd-present chromium` returns true and all the Chromium-touching omarchy scripts (webapp launcher, theme-set-browser, policy refreshes) find it on PATH. The shim passes `--user-data-dir="$HOME/.config/chromium"` so Flatpak chromium stores its config at the standard path — not the sandbox `~/.var/app/…/` — which is where `omarchy-theme-set-browser` writes the managed policy file and where `~/.config/chromium-flags.conf` lives. Two matching `flatpak override --system --filesystem=…` calls in `build.sh` grant the sandbox access needed for that redirection.

All four ride the `flatpak-preinstall.service` pipeline — drop a `.preinstall` file under `files/usr/share/flatpak/preinstall.d/` and the service reruns whenever that directory changes. Flathub is pre-added system-wide.

## Build & release

### Repo layout

```
Containerfile
Justfile
build_files/
  build.sh                     # entry point; pinned tags; orchestration
  repos.sh                     # COPR / repo setup
  packages.sh                  # dnf5 installs
  source-builds.sh             # all source builds
  desktop.sh                   # SDDM + omarchy
files/
  etc/sddm.conf.d/
  usr/bin/atomic-hyprland-*
  usr/lib/systemd/system/
  usr/lib/sysusers.d/
  usr/share/flatpak/preinstall.d/
  usr/share/ublue-os/just/60-custom.just
.github/workflows/build.yml
```

### Containerfile shape

```dockerfile
ARG FEDORA_VERSION=…
FROM scratch AS ctx
COPY build_files /

FROM ghcr.io/ublue-os/base-main:${FEDORA_VERSION}
COPY files/ /
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build.sh \
 && ostree container commit
RUN bootc container lint
```

`build.sh` is bind-mounted and never persists in the image. `bootc container lint` validates the result.

### CI

Builds on push to `main`, PRs, weekly schedule (`0 4 * * 1`), and manual dispatch. Pushes to GHCR via `GITHUB_TOKEN`. PR builds produce `:pr-<N>`; main/schedule produce `:<fedora-ver>`, `:latest`, and a dated snapshot.

### Pinned vs unpinned refs

| Ref | Policy |
|---|---|
| Hyprland ecosystem + non-hyprwm source builds | Pinned tags in `build.sh` |
| `basecamp/omarchy` | Unpinned — weekly CI picks up main |
| Fedora packages / COPRs / Docker CE / VS Code | Unpinned |

Upgrading a pinned ref is a one-line change in `build.sh` → CI builds `:pr-<N>` → rebase to test → merge.

## Update flow

- `ujust update` (or automatic nightly) pulls the latest image via `rpm-ostree upgrade`.
- Flatpak and Homebrew updates are chained by `ujust update`.
- After a rebuild that includes new dotfiles, `ujust sync-skel-config overwrite=1` applies them to `$HOME`.
- Rollback: `sudo bootc rollback && systemctl reboot`.

## Upstream attribution

| Area | Source |
|---|---|
| `Containerfile` (two-stage + cache mounts + lint) | `ublue-os/image-template` |
| `Justfile` | `ublue-os/image-template` (trimmed) |
| Container stack in `packages.sh` | `ublue-os/bluefin` → `build_files/dx/00-dx.sh` |
| `copr_install_isolated` helper | `ublue-os/bluefin` → `build_files/shared/copr-helpers.sh` |
| `atomic-hyprland-dx-groups` script + service | `ublue-os/bluefin` → `bluefin-dx-groups` |
| SDDM theme | `basecamp/omarchy` (ships `default/sddm/omarchy/`) |
| Desktop rice | `basecamp/omarchy` |

## Risks

- **Fedora version bump breaks a package** — weekly CI catches it before `rpm-ostree upgrade` lands.
- **Upstream rice change breaks the image** — weekly CI catches it; rollback is one command.
- **Source-build breaks on new upstream release** — all tags are pinned; the old build still works until a deliberate bump PR passes CI.
