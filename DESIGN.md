# Atomic-Hyprland — Design

A personal Fedora Atomic image that ships Hyprland with [LinuxBeginnings/Hyprland-Dots](https://github.com/LinuxBeginnings/Hyprland-Dots) on top of Universal Blue's `base-main`. Single-user scope, AMD GPU, no nvidia variant.

This file describes **intent and invariants**. For current values (pinned tags, package list, Fedora version) look at [`build_files/build.sh`](./build_files/build.sh); it is the source of truth.

## Goals

- Fedora Atomic base with Universal Blue's plumbing (auto-updates, `ujust`, Homebrew).
- First-boot-ready desktop: full rice baked in, no post-install package commands.
- Automatic upgrade path via `rpm-ostree`/`bootc` with zero manual pin maintenance for fast-moving components.
- Minimal repo surface: raw `Containerfile` + `build.sh` + static `files/` overlay.
- Personal use only — no user-facing CLI wrappers beyond one `ujust` recipe, no welcome flows, no ISO, no signing.

## Architecture

- **Base image:** `ghcr.io/ublue-os/base-main`, Fedora version pinned in `Containerfile`/CI. Bumping Fedora is a deliberate PR.
- **Build framework:** raw two-stage `Containerfile` + `build.sh`. No BlueBuild; a single image doesn't benefit from BlueBuild's recipe matrix.
- **Image:** `ghcr.io/<gh-user>/atomic-hyprland`, public GHCR.
- **Signing:** none. Rebase via `ostree-unverified-registry:` / `bootc switch`. Single-user personal threat model accepts GitHub-account hygiene as mitigation. Adding cosign later is a non-breaking change.
- **Distribution tags:** `:<fedora-ver>`, `:latest`, `:<fedora-ver>-<YYYYMMDD>`, `:pr-<N>`.

### Why these choices

- `base-main` over `bluefin`/`bazzite`/`aurora`: those ship GNOME/KDE. `base-main` is clean Fedora Atomic with uBlue plumbing already installed.
- `solopasha/hyprland` COPR over Fedora-packaged Hyprland: tracks upstream closely, packages the full `hypr*` ecosystem. Both reference projects ([`cjuniorfox/hyprland-atomic`](https://github.com/cjuniorfox/hyprland-atomic), [`wayblueorg/wayblue`](https://github.com/wayblueorg/wayblue)) use it.

## Package layering

Actual package list lives in `build_files/build.sh`. Categories:

- **Hyprland ecosystem** from `solopasha/hyprland` COPR (hyprland, hyprlock, hypridle, hyprpaper, hyprcursor, hyprsunset, xdg-desktop-portal-hyprland, etc.). `hyprland-qtutils`/`hyprpolkitagent` are currently excluded — see "Qtutils workaround" below.
- **Session/greeter** (Qt6 only) — `sddm` + the Qt6 modules the astronaut theme needs. Qt5 is deliberately excluded.
- **Desktop apps:** ghostty + kitty (kitty is kept because Hyprland-Dots references it, ghostty is user default), waybar, rofi-wayland, swaync, nautilus, clipboard, screenshot, network/BT applets, audio UIs, portals, polkit (mate-polkit as agent), display helpers, uwsm, gvfs.
- **Developer tooling:** VS Code (layered RPM), `make` + C/C++ headers + sqlite-devel + python3-pip for occasional pip-builds-from-source. Everything else (rg/fd/fzf/jq/btop/lazygit/yazi/…) deferred to `brew` per uBlue-DX philosophy.
- **Container stack:** full uBlue Bluefin-DX parity — `podman-compose`/`podman-tui`/`flatpak-builder` plus Docker CE via the disable-then-`--enablerepo` pattern.
- **GPU compute:** ROCm user-space (`rocm-hip`, `rocm-opencl`, `rocm-smi`) for AMD scientific compute.
- **Fonts + theming:** Fedora fonts plus `che/nerd-fonts` COPR's all-families `nerd-fonts` package (installed isolated so the COPR is not left enabled), icons, `kvantum`.

### Repo enablement policy

- **Left enabled** on the running system — so `rpm-ostree upgrade` picks up live updates: `solopasha/hyprland`, `pgdev/ghostty`, Microsoft VS Code, Docker CE (repo file `enabled=0` by default, `--enablerepo=docker-ce-stable` at install time).
- **Enabled → install → disabled** during build: `che/nerd-fonts` via the `copr_install_isolated` helper copied from [`ublue-os/bluefin`](https://github.com/ublue-os/bluefin/blob/main/build_files/shared/copr-helpers.sh). No `.repo` file survives in the final image.

### Inherited from `base-main`

`base-main`'s [`build_files/install.sh`](https://github.com/ublue-os/main/blob/main/build_files/install.sh) already layers: `ublue-os-just` (`ujust`), `ublue-os-signing`, `ublue-os-update-services` (auto-update timers + `ublue-update`), `ublue-os-udev-rules`, `ublue-os-luks`, Homebrew, Flatpak, podman, distrobox, PipeWire/WirePlumber, NetworkManager, rpm-ostree, `rpm-ostreed-automatic.timer`.

We additionally enable at build: `sddm.service`, `docker.socket`, `podman.socket`, `flatpak-system-update.timer`, `flatpak-user-update.timer`, `podman-auto-update.timer`, `atomic-hyprland-dx-groups.service`, `install-zen-browser.service`.

### Deliberately omitted

`earlyoom` (systemd-oomd handles this better on modern Fedora), `cmake`/`meson`/`ninja-build`/`python3-devel` (not compiling C/C++), libvirt/qemu (VM scope), cockpit, kernel tracing tools.

A few things that couldn't ship from Fedora repos were pushed to user action: `yazi` via brew, `eduvpn-client` via pipx/Flatpak, cursor themes via Hyprland-Dots' own install.

## Desktop environment — LinuxBeginnings/Hyprland-Dots

The full Hyprland-Dots tree is cloned unpinned (master) during each build and copied into `/etc/skel/.config/`. Rationale:

- Hyprland-Dots evolves rapidly (waybar modules, keybinds, scripts). We want updates automatically; pinning would create maintenance churn. Weekly CI picks up master every week.
- Running the upstream `copy.sh` post-rebase was rejected: it is heavily interactive (whiptail prompts for keyboard/resolution/animations), hard-codes `$HOME`, and its runtime-only knobs can be fixed at bake time for our single-user AMD-GPU profile.
- Predecessor HyDE (Arch-only installer) and `LinuxBeginnings/Fedora-Hyprland` (mutable-Fedora-only, uses `sudo dnf install`) are both Atomic-incompatible. Only `LinuxBeginnings/Hyprland-Dots` (dotfiles-only, package-manager-free) is safe to bake.

### Baked-in overrides

`build.sh` applies two sed/append patches on top of the cloned Hyprland-Dots tree before copying to `/etc/skel`:

1. **Default terminal:** `$term = kitty` → `$term = ghostty` in `UserConfigs/01-UserDefaults.conf`. Kitty stays installed because the theme switcher references it.
2. **Qtutils warning suppression:** append a `misc { disable_hyprland_guiutils_check = true }` block to `UserConfigs/UserSettings.conf`. See "Qtutils workaround" below.

### Applying the skel to existing `$HOME`

`/etc/skel` only copies to `$HOME` on new-user creation. Accounts carried over from an earlier deployment already exist and will not inherit the skel. A `ujust` recipe rsyncs `/etc/skel/` into `$HOME`:

```sh
ujust sync-skel-config              # safe -- skips files that already exist
ujust sync-skel-config overwrite=1  # clobber existing files from the new skel
```

The recipe lives at `/usr/share/ublue-os/just/60-custom.just` — uBlue's sanctioned extension point (`base-main`'s justfile already `import?`'s this path).

### Qtutils workaround

`hyprland-qtutils` and `hyprpolkitagent` from the `solopasha/hyprland` COPR depend on `hyprland-qt-support` built against a Qt6 private ABI that does not match Fedora's current Qt6. dnf cannot resolve the transaction. The same situation affects `cjuniorfox/hyprland-atomic`; this is a Fedora-ecosystem issue, not specific to this image.

Mitigations:

- **Polkit agent:** use `mate-polkit` instead of `hyprpolkitagent`. Hyprland-Dots' `Polkit.sh` walks a candidate list and picks mate-polkit automatically.
- **Suppress the `hyprland-dialog` missing notification** that Hyprland fires at startup: set `misc:disable_hyprland_guiutils_check = true` (upstream-sanctioned config flag) via the override above.

Cleanup when upstream fixes this is tracked in [issue #1](https://github.com/oameye/atomic-hyprland/issues/1). Upstream blocker: [`hyprwm/hyprland-qt-support#9`](https://github.com/hyprwm/hyprland-qt-support/issues/9).

## SDDM greeter

Pre-baked at image build time because SDDM themes and the Hyprland-compositor-hosted greeter integration both write to `/usr/share/`, which is read-only post-boot on rpm-ostree.

- **[`HyDE-Project/sddm-hyprland`](https://github.com/HyDE-Project/sddm-hyprland)** — pinned tag. `make install PREFIX=/usr` drops the Hyprland config + SDDM conf files that set `CompositorCommand=Hyprland`. Qt6-compatible.
- **[`Keyitdev/sddm-astronaut-theme`](https://github.com/Keyitdev/sddm-astronaut-theme)** — pinned commit + variant choice. Cloned into `/usr/share/sddm/themes/`, its bundled fonts are copied into `/usr/share/fonts/`, and `metadata.desktop` is sed-patched to select the variant.
- **Static configs** shipped via `files/etc/sddm.conf.d/`: `theme.conf` (Current=…), `virtualkbd.conf` (astronaut theme's qtvirtualkeyboard input), plus an empty legacy marker file that keeps any future HyDE reintroduction quiet.

## Browser

No browser is layered as RPM; `base-main`'s Firefox is `override remove`d. [Zen Browser](https://zen-browser.app/) is auto-installed on first boot via a systemd oneshot that calls `flatpak install flathub app.zen_browser.zen` (the Flathub remote itself is pre-added system-wide during build). Known Flatpak-browser trade-offs (`~/.var/app/…` paths, portal-mediated file access, sandboxed native-messaging) are accepted.

## Build & release

### Repo layout

```
Containerfile                  # two-stage: scratch ctx + base-main
Justfile                       # local-dev recipes (build/lint/format/clean)
build_files/
  build.sh                     # bind-mounted into the build, never lands in image
files/                         # COPY'd into final image
  etc/systemd/system/install-zen-browser.service
  etc/sddm.conf.d/*.conf
  usr/bin/atomic-hyprland-dx-groups
  usr/lib/systemd/system/atomic-hyprland-dx-groups.service
  usr/lib/sysusers.d/atomic-hyprland.conf
  usr/share/ublue-os/just/60-custom.just
.github/workflows/build.yml
README.md
DESIGN.md
```

### Containerfile shape

Pattern lifted from [`ublue-os/image-template`](https://github.com/ublue-os/image-template):

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

Key properties: `build.sh` is bind-mounted so it never persists in the image; cache mounts speed local iteration; `bootc container lint` validates the result.

### `build.sh` responsibilities (in order)

1. Enable live-use COPRs (`solopasha/hyprland`, `pgdev/ghostty`) via curl-to-`/etc/yum.repos.d/`.
2. Define the `copr_install_isolated` helper (verbatim from [`ublue-os/bluefin`](https://github.com/ublue-os/bluefin/blob/main/build_files/shared/copr-helpers.sh)).
3. Drop the VS Code repo file and the Docker CE repo file (latter `enabled=0`).
4. `dnf5 -y install --setopt=install_weak_deps=False` the full package set; then install Docker CE via `--enablerepo=docker-ce-stable`.
5. `rpm-ostree override remove firefox firefox-langpacks`.
6. Install `nerd-fonts` via `copr_install_isolated "che/nerd-fonts" "nerd-fonts"`.
7. **SDDM greeter + theme + Hyprland-Dots rice** (all in one scratch dir):
   - Clone `HyDE-Project/sddm-hyprland` at pinned tag → `make install PREFIX=/usr`.
   - Clone `Keyitdev/sddm-astronaut-theme` at pinned commit → install into `/usr/share/sddm/themes/`, copy its fonts, sed the variant.
   - Clone `LinuxBeginnings/Hyprland-Dots` unpinned → copy `config/` → `/etc/skel/.config/`, apply baked-in overrides (ghostty default, qtutils suppression).
8. Pre-add Flathub system-wide (`flatpak remote-add --if-not-exists --system flathub …`).
9. Enable systemd units (sddm, docker/podman sockets, update timers, dx-groups, zen-browser).
10. Clean `/var/cache/dnf`, `/var/lib/dnf`, `/var/lib/blueman`, `/tmp/*` for image-size hygiene and bootc lint compliance.

### CI

GitHub Actions builds on push to `main`, PRs, weekly schedule, and manual dispatch; pushes to GHCR using `GITHUB_TOKEN`. PR builds emit `:pr-<N>`; main/schedule emit `:<fedora-ver>` + `:latest` + dated snapshot.

### Pinned vs unpinned upstream refs

| | Policy | Why |
|---|---|---|
| `HyDE-Project/sddm-hyprland` | Pinned tag | Greeter should not change visually under the user |
| `Keyitdev/sddm-astronaut-theme` | Pinned commit + variant | Same |
| `LinuxBeginnings/Hyprland-Dots` | Unpinned (master) | Fast-moving rice; weekly CI picks up upstream automatically |
| Fedora / COPRs / Docker CE / VS Code | Unpinned | Normal package manager behaviour |

Upgrading a pinned ref is a one-string PR in `build.sh` → CI builds `:pr-<N>` → rebase-to-test → merge. Unpinned refs flow automatically on weekly CI builds.

## Update flow

User workflow is identical to Aurora/Bluefin:

- `ujust update` or `rpm-ostree upgrade` pulls the latest `:<fedora-ver>` from our GHCR. `rpm-ostreed-automatic.timer` does this nightly in the background.
- Flatpak and Homebrew updates are chained by `ujust update`; Flatpak has its own auto-update timers too.
- After a rebuild lands new dotfiles, `ujust sync-skel-config overwrite=1` pulls them into `$HOME`.
- Rollback: `sudo bootc rollback && systemctl reboot` (or `rpm-ostree rollback`).

## Upstream fidelity

Files and patterns copied from upstream rather than invented. If the upstream source changes substantially, audit and update:

| Area | Upstream source |
|---|---|
| `Containerfile` (two-stage + cache mounts + `bootc container lint`) | `ublue-os/image-template` |
| `Justfile` | `ublue-os/image-template` (trimmed — VM/ISO recipes dropped) |
| Container stack section of `build.sh` | `ublue-os/bluefin` → `build_files/dx/00-dx.sh` |
| `copr_install_isolated` helper | `ublue-os/bluefin` → `build_files/shared/copr-helpers.sh` |
| `che/nerd-fonts` → `nerd-fonts` install pattern | `ublue-os/bluefin` → `build_files/base/04-packages.sh` |
| `atomic-hyprland-dx-groups` script + service | `ublue-os/bluefin` → `system_files/dx/usr/{bin,lib/systemd/system}/bluefin-dx-groups{,.service}` |
| SDDM Wayland-compositor integration | `HyDE-Project/sddm-hyprland` |
| SDDM theme | `Keyitdev/sddm-astronaut-theme` |
| Full rice in `/etc/skel/.config/` | `LinuxBeginnings/Hyprland-Dots` |

## Risks & mitigations

- **Fedora version bump breaks a layered package** (VS Code is the usual culprit): weekly CI catches it before your laptop pulls the upgrade.
- **Upstream rice change breaks the image**: weekly CI catches it before `rpm-ostree upgrade`. Rollback is always one command.
- **solopasha COPR outage or conflict**: fall back to Fedora's `hyprland` package as a temporary patch; the COPR is re-enabled once fixed.
- **Unsigned image tampering**: mitigated by GitHub 2FA/recovery hygiene. An attacker with GitHub push access could still inject a build; `rpm-ostree rollback` recovers post-hoc.
