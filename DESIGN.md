# Atomic-Hyprland — Design

A personal Fedora Atomic image shipping Hyprland with [LinuxBeginnings/Hyprland-Dots](https://github.com/LinuxBeginnings/Hyprland-Dots) on top of Universal Blue's `base-main`. Single-user, AMD GPU only.

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
- **Session / greeter** — `sddm` + Qt6 modules the astronaut theme needs + `layer-shell-qt`.
- **Desktop runtime** — packages Hyprland-Dots scripts and configs expect: waybar, rofi-wayland, swaync, quickshell, nautilus, ghostty, kitty, wl-clipboard, grim/slurp/swappy, audio stack, wallust, mpv, btop, fastfetch, etc.
- **Qt theming** — `qt5ct` + `kvantum-qt5` (Qt5) and `qt6ct` + `qt6-qt5compat` (Qt6) for full Hyprland-Dots theme switching.
- **Developer tooling** — VS Code (RPM), make, gcc-c++. Everything else (`fd`, `fzf`, `lazygit`, `yazi`, …) via `brew`.
- **Containers** — `podman-compose`, `podman-tui`, `podman-machine`, `flatpak-builder`, Docker CE.
- **GPU compute** — ROCm user-space (`rocm-hip`, `rocm-opencl`, `rocm-smi`) for AMD.
- **Fonts + theming** — Fedora fonts, `nerd-fonts` (from `che/nerd-fonts` COPR, isolated install), `adwaita-icon-theme`, `papirus-icon-theme`, `kvantum`.

### COPR policy

- **Left enabled** — `pgdev/ghostty`, `errornointernet/quickshell`, VS Code, Docker CE (`enabled=0`, used via `--enablerepo`).
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

Build-only toolchains (cmake, meson, rust/cargo, golang, Qt6 devel) are removed after all builds complete.

## Desktop environment

`LinuxBeginnings/Hyprland-Dots` is cloned unpinned (master) each build and copied into `/etc/skel/.config/`. It tracks master because the rice evolves rapidly and weekly CI picks up changes automatically.

### Baked-in overrides

Applied as sed patches in `desktop.sh`:

- `$term = ghostty` (upstream default: kitty)
- `$files = nautilus` (upstream default: thunar)

### Applying the skel to an existing `$HOME`

`/etc/skel` only populates `$HOME` on new-user creation. A `ujust` recipe handles existing accounts:

```sh
ujust sync-skel-config              # merge — skips files that already exist
ujust sync-skel-config overwrite=1  # replace managed subtrees from the new skel
```

## SDDM greeter

- **[`HyDE-Project/sddm-hyprland`](https://github.com/HyDE-Project/sddm-hyprland)** — pinned tag, `make install PREFIX=/usr`. Sets `CompositorCommand=Hyprland`.
- **[`Keyitdev/sddm-astronaut-theme`](https://github.com/Keyitdev/sddm-astronaut-theme)** — pinned commit, cloned to `/usr/share/sddm/themes/`. Bundled fonts copied to `/usr/share/fonts/`. Variant selected by sed-patching `metadata.desktop`.
- Static configs in `files/etc/sddm.conf.d/`: `theme.conf`, `virtualkbd.conf`.

## Browser

Firefox is removed (`rpm-ostree override remove`). [Zen Browser](https://zen-browser.app/) is installed via `flatpak-preinstall.service`, which reruns only when `/usr/share/flatpak/preinstall.d/*.preinstall` changes. Flathub is pre-added system-wide.

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
  desktop.sh                   # SDDM + Hyprland-Dots
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
| `HyDE-Project/sddm-hyprland` | Pinned tag |
| `Keyitdev/sddm-astronaut-theme` | Pinned commit |
| Hyprland ecosystem + non-hyprwm source builds | Pinned tags in `build.sh` |
| `LinuxBeginnings/Hyprland-Dots` | Unpinned — weekly CI picks up master |
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
| SDDM integration | `HyDE-Project/sddm-hyprland` |
| SDDM theme | `Keyitdev/sddm-astronaut-theme` |
| Desktop rice | `LinuxBeginnings/Hyprland-Dots` |

## Risks

- **Fedora version bump breaks a package** — weekly CI catches it before `rpm-ostree upgrade` lands.
- **Upstream rice change breaks the image** — weekly CI catches it; rollback is one command.
- **Source-build breaks on new upstream release** — all tags are pinned; the old build still works until a deliberate bump PR passes CI.
