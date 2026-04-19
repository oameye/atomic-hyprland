# Atomic-Hyprland — Design

A personal Fedora Atomic image that ships Hyprland on top of Universal Blue's `base-main`, with HyDE as the post-rebase rice. Single-user scope (AMD GPU, no nvidia variant).

This document reflects the **as-built** design. During first implementation, several F43-repo-reality constraints forced package deviations from the original design: the Qt5 stack and HyDE's Qt5-based SDDM themes were dropped, `hyprpolkitagent`/`hyprland-qtutils` were replaced with `mate-polkit` due to a Qt6.9-vs-6.10 ABI conflict in solopasha's COPR, and `yazi`/`eduvpn-client`/`bibata-cursor-themes` moved off the bake-in list (they are not in F43 repos). Each deviation is called out in its section below with rationale.

## Goals

- Fedora Atomic base with Universal Blue's plumbing (auto-updates, signing infra, `ujust`, Homebrew setup).
- Hyprland + a full opinionated desktop stack baked in, so first boot is a working system.
- Easy, automatic upgrades via `rpm-ostree`.
- Minimal maintenance surface: raw Containerfile, no BlueBuild.
- Personal use only — no user-facing CLI wrappers, no welcome flows, no ISO, no signing.

## Architecture

- **Base image:** `ghcr.io/ublue-os/base-main:43`
- **Build framework:** Raw `Containerfile` + `build.sh`, loosely based on `ublue-os/image-template`.
- **Image name:** `ghcr.io/<gh-user>/atomic-hyprland`
- **Signing:** None. Rebase via `ostree-unverified-registry:`. Trade-off accepted: we lose tamper detection on updates in exchange for simpler setup. Threat model is personal (single user, trusted GitHub account); cost of signing is low but benefit is also low.
- **Repository visibility:** Public GitHub repo + public GHCR image. Public repos get free/unlimited GitHub Actions minutes. GHCR packages default to private on first push and must be flipped to public manually (*GitHub → Profile → Packages → atomic-hyprland → Package settings → Change visibility*) before `rpm-ostree rebase` works anonymously.
- **Fedora version:** Pinned to `43`. Bumping to 44+ is a deliberate PR.

### Why these choices

- `base-main` over `bluefin`/`bazzite`/`aurora`: those ship GNOME/KDE, which we would have to rip out. `base-main` is a clean Fedora Atomic with uBlue's plumbing already layered.
- Raw Containerfile over BlueBuild: a single personal image does not benefit from BlueBuild's recipe-matrix abstraction. Matches `cjuniorfox/hyprland-atomic`'s approach; `wayblueorg/wayblue` uses BlueBuild because it maintains 36 recipe variants.
- `solopasha/hyprland` COPR over Fedora's packaged Hyprland: tracks upstream closely (Fedora lags 1–3 versions) and packages the whole `hypr*` ecosystem uniformly. Both reference projects use it.

## Package Layering

Installed via `rpm-ostree install` in `build.sh`.

### Extra repos enabled at build time

- `solopasha/hyprland` COPR (left enabled post-install so `rpm-ostree upgrade` can pull live Hyprland updates between weekly CI rebuilds)
- `pgdev/ghostty` COPR (left enabled, same reason)
- `che/nerd-fonts` COPR — installed via `copr_install_isolated` helper copied from uBlue Bluefin (COPR enabled → disabled → install via one-shot `--enablerepo`, so no `.repo` file lives in the final image). Ships a single mega-package `nerd-fonts` with all Nerd Font families.
- Microsoft VS Code repo (`packages.microsoft.com/yumrepos/vscode`)
- Docker CE repo (`download.docker.com/linux/fedora/docker-ce.repo`) — disabled after install per uBlue pattern

### Hyprland ecosystem (from solopasha COPR)

`hyprland`, `hyprlock`, `hypridle`, `hyprpaper`, `hyprshot`, `hyprpicker`, `hyprcursor`, `hyprsunset`, `xdg-desktop-portal-hyprland`

**Dropped during implementation:** `hyprpolkitagent`, `hyprland-qtutils`. Both depend on solopasha's `hyprland-qt-support-0.1.0-8.fc43`, which requires `Qt_6.9_PRIVATE_API`. Fedora 43 updates ships Qt6.10.3; the ABI break leaves dnf unable to resolve the dep chain. `mate-polkit` (below) replaces hyprpolkitagent as the polkit auth agent. Revisit when solopasha rebuilds against Qt6.10.

### Session / greeter (Qt6 only)

`sddm`, `sddm-themes`, `layer-shell-qt`, `qt6-qtsvg`, `qt6-qtmultimedia`, `qt6-qtdeclarative`

All Qt5 packages are deliberately excluded. HyDE's SDDM themes (Candy/Corners) use Qt5 QML imports and are therefore not used — we ship Fedora's stock `sddm-themes` package and select the `maldives` theme via `/etc/sddm.conf.d/theme.conf`. `layer-shell-qt` is Qt6 (only variant packaged in F43) and powers the `sddm-hyprland` Wayland-compositor-hosted greeter.

### Desktop applications (Fedora repos)

- Terminal: `ghostty`
- Bar: `waybar`
- Launcher: `rofi-wayland`
- Notifications: `swaync`
- File manager: `nautilus`, `nautilus-python` (`yazi` not in F43 repos → install via `brew install yazi`)
- Clipboard: `wl-clipboard`, `cliphist`
- Screenshots: `grim`, `slurp`, `satty` (annotation)
- Network / Bluetooth: `network-manager-applet`, `blueman`, `bluez-tools`
- Audio UI: `pavucontrol`, `playerctl`, `pamixer`
- Portals: `xdg-desktop-portal-gtk`
- Polkit: `polkit` + `mate-polkit` (GTK-based authentication agent; replaces first-party `hyprpolkitagent` which is broken by the Qt6 ABI conflict above)
- Display helpers: `brightnessctl`, `wlr-randr` (nightlight handled by `hyprsunset` above)
- Session manager: `uwsm` (systemd user-slice scoping for Hyprland session and app launches)
- Filesystem helpers: `gvfs`, `gvfs-mtp`, `gvfs-smb`

### Developer tooling

- **Editor:** `code` (VS Code, layered from Microsoft's RPM repo)
- **Homebrew:** inherited from `base-main` (no action). All CLI ergonomics — `ripgrep`, `fd-find`, `fzf`, `jq`, `yq`, `btop`, `lazygit`, `git-delta`, `yazi`, etc. — are deferred to brew. Matches uBlue DX's philosophy of "system-level infra on the host, CLI tooling via brew."
- **Build essentials:** `make` (scientific Python/R packages occasionally need it at install time)
- **Carried over from current Aurora layered packages:** `gcc-c++`, `libstdc++-devel`, `python3-pip`, `sqlite-devel` (kept in case `pip install` builds a native extension from source)
- **VPN:** `eduvpn-client` is not in Fedora 43 repos (all candidate COPRs empty). Install post-boot via `pipx install eduvpn-gui` or the community Flatpak. Not baked in.

### Container stack (parity with uBlue Bluefin-DX / Aurora-DX)

**Principle:** do not reinvent uBlue's container stack setup. Mirror the upstream [`build_files/dx/00-dx.sh`](https://github.com/ublue-os/bluefin/blob/main/build_files/dx/00-dx.sh) pattern verbatim in our `build.sh` for the container-stack portion. Copy the `bluefin-dx-groups` helper (rename to `atomic-hyprland-dx-groups`) so wheel members are added to `docker`/`incus-admin`/`libvirt` groups on first boot.

Packages installed (from Fedora):

- `podman-compose`, `podman-tui`, `podman-machine`, `flatpak-builder`
- `distrobox`, `podman` — already in `base-main` (no action)

Docker CE installed using uBlue's exact disable-then-`--enablerepo` pattern so the Docker repo is present but not consulted during `rpm-ostree upgrade` by default:

```bash
dnf5 config-manager addrepo --from-repofile=https://download.docker.com/linux/fedora/docker-ce.repo
sed -i "s/enabled=.*/enabled=0/g" /etc/yum.repos.d/docker-ce.repo
dnf5 -y install --enablerepo=docker-ce-stable \
    docker-ce docker-ce-cli docker-compose-plugin \
    docker-buildx-plugin containerd.io
```

Systemd units enabled at build time:

- `docker.socket`, `podman.socket`
- `atomic-hyprland-dx-groups.service` — oneshot that appends `docker`, `incus-admin`, `libvirt` entries to `/etc/group` (copied from `/usr/lib/group`) and adds wheel members to them. Vendored from [`system_files/dx/usr/bin/bluefin-dx-groups`](https://github.com/ublue-os/bluefin/blob/main/system_files/dx/usr/bin/bluefin-dx-groups) + [`.../bluefin-dx-groups.service`](https://github.com/ublue-os/bluefin/blob/main/system_files/dx/usr/lib/systemd/system/bluefin-dx-groups.service) with a one-line rename.

### Upstream fidelity — files we track for drift

The following pieces are copied-from-upstream rather than invented. If uBlue changes them we should audit and update:

| Our file | Upstream source |
|---|---|
| `build.sh` (container-stack section) | `ublue-os/bluefin` → `build_files/dx/00-dx.sh` |
| `build.sh` (`copr_install_isolated` helper) | `ublue-os/bluefin` → `build_files/shared/copr-helpers.sh` |
| `build.sh` (`che/nerd-fonts` → `nerd-fonts` install pattern) | `ublue-os/bluefin` → `build_files/base/04-packages.sh` |
| `Containerfile` (two-stage ctx + cache mounts + `bootc container lint`) | `ublue-os/image-template` → `Containerfile` |
| `Justfile` (local-dev recipes) | `ublue-os/image-template` → `Justfile` (trimmed; VM/ISO recipes dropped) |
| `files/usr/bin/atomic-hyprland-dx-groups` | `ublue-os/bluefin` → `system_files/dx/usr/bin/bluefin-dx-groups` |
| `files/usr/lib/systemd/system/atomic-hyprland-dx-groups.service` | `ublue-os/bluefin` → `system_files/dx/usr/lib/systemd/system/bluefin-dx-groups.service` |
| SDDM greeter integration | `HyDE-Project/sddm-hyprland` (pinned tag `v0.48.0`, `make install`-ed at build time) |
| SDDM theme | `Keyitdev/sddm-astronaut-theme` (pinned commit `d73842c`, variant `astronaut`; cloned + fonts copied) |
| `/etc/skel/.config/*` (full Hyprland rice) | `LinuxBeginnings/Hyprland-Dots` (**unpinned** master; weekly CI picks up upstream automatically) |

### GPU compute (AMD ROCm)

- `rocm-hip`, `rocm-opencl`, `rocm-smi`
- Matches the AMD RX 6650 XT target hardware and typical scientific-computing workload.

### Omitted

- **`earlyoom`** was on the Aurora layered list but is deliberately not carried over. `base-main` enables `systemd-oomd`, which uses PSI (actual memory pressure) rather than earlyoom's free-memory thresholds. Running both is counterproductive.
- **`cmake`, `meson`, `ninja-build`, `pkgconf-pkg-config`, `python3-devel`** — user does not actively compile C/C++ code. If a `pip install` needs them later they can be added.
- **`libvirt` / `virt-manager` / `qemu-*`** — VM use out of scope.
- **Cockpit** — web admin UI not used in a Hyprland desktop workflow.
- **`bpftrace`, `bcc`, `sysprof`, `trace-cmd`** — kernel tracing not in active workflow.

### Fonts and theming

- Fonts: `fontawesome-fonts-all`, `google-noto-emoji-fonts`, `liberation-fonts`, `jetbrains-mono-fonts` from Fedora; plus `nerd-fonts` (all Nerd Font families) installed isolated from the `che/nerd-fonts` COPR, matching the Bluefin pattern
- Icons: `adwaita-icon-theme`, `papirus-icon-theme`
- Qt theming engine: `kvantum` (required by HyDE's theme switcher to keep Qt apps in sync with the active theme)
- Cursors: `bibata-cursor-themes` is not in Fedora 43 repos; HyDE installs its own cursor theme into `~/.icons` via its post-install script, so no system-level cursor theme is baked in.

### Inherited from `base-main` (not re-installed)

Verified against `ublue-os/main` → `build_files/install.sh` (which installs `ublue-os-just`, `ublue-os-luks`, `ublue-os-signing`, `ublue-os-udev-rules`, `ublue-os-update-services` from the `ublue-os/packages` COPR and then disables the COPR):

PipeWire + WirePlumber, Flatpak, podman, distrobox, NetworkManager, rpm-ostree, `ublue-os-signing`, `ublue-os-just` (provides `ujust`), `ublue-os-update-services` (provides `ublue-update` + automatic timers), `ublue-os-udev-rules`, `ublue-os-luks`, Homebrew setup unit, `rpm-ostreed-automatic.timer`.

## Desktop Environment ([LinuxBeginnings/Hyprland-Dots](https://github.com/LinuxBeginnings/Hyprland-Dots))

### History — why not HyDE

The original plan was to run [HyDE-Project/HyDE](https://github.com/HyDE-Project/HyDE) post-rebase. First on-system test revealed two hard blockers:

1. **HyDE is Arch-only.** Its README explicitly says so; the installer calls `pacman`/AUR helpers and fails on Fedora, prompting to install `yay`/`paru` on an Atomic system. HyDE's `pm.sh` lists `dnf` in a supported-package-managers array but multiple other install paths hard-code Arch assumptions.
2. **Hyprland's stock `/usr/share/hyprland/hyprland.conf` fallback binds `SUPER+Q` to `kitty`** — we had ghostty but not kitty at the time, so without a rice the user had no working terminal keybind and had to reach a TTY to recover.

We switched to **LinuxBeginnings/Hyprland-Dots** (successor to JaKooLit/Hyprland-Dots — both authors archived the JaKooLit org in March 2026). `LinuxBeginnings/Fedora-Hyprland` (the **installer** repo) still uses `sudo dnf install` and is not Atomic-compatible. **`LinuxBeginnings/Hyprland-Dots` (the dotfiles-only repo)** is package-manager-free — `copy.sh` writes only to `~/.config`, grep confirms no `dnf install`/`pacman`/`apt` calls — and works fine on Atomic once packages are baked.

### Baked into `/etc/skel` at build time

We clone `LinuxBeginnings/Hyprland-Dots` **unpinned** (master) during every image build and copy `config/` → `/etc/skel/.config/`. This gives low-maintenance + automatic updates: weekly CI pulls the latest master automatically, no manual submodule bumps on our side.

Pattern chosen over running `copy.sh` post-boot because `copy.sh` is heavily interactive (whiptail menus, keyboard/resolution/animation prompts) and hard-codes `$HOME` paths — it's not safe to run non-interactively in a Containerfile against `/etc/skel`, and defaults can be hard-coded at bake time (AMD GPU, no Nvidia branches, US keyboard).

### Baked-in overrides

During the build, `build.sh` applies two patches on top of the Hyprland-Dots tree:

1. **Ghostty as default terminal.** Hyprland-Dots ships `$term = kitty` in `01-UserDefaults.conf`. We sed-patch it to `$term = ghostty`. Kitty is still installed because Hyprland-Dots' theme switcher (`Kitty_themes.sh`) references it.
2. **Silence the `hyprland-qtutils missing` notification overlay.** We append a `misc { disable_hyprland_guiutils_check = true }` block to `UserConfigs/UserSettings.conf`. Rationale in the next section.

### `hyprland-qtutils` warning suppression

`hyprland-qtutils` and `hyprpolkitagent` (both from `solopasha/hyprland` COPR) depend on `hyprland-qt-support-0.1.0-8.fc43`, which requires `Qt_6.9_PRIVATE_API` symbols. Fedora 43 updates ships Qt6.10, so the COPR packages cannot be installed — a dependency resolution conflict. We drop them from the package list and use `mate-polkit` as the polkit auth agent instead (Hyprland-Dots' `Polkit.sh` walks a list of agent paths including `/usr/libexec/polkit-mate-authentication-agent-1` and picks mate-polkit automatically).

But Hyprland itself still checks for `hyprland-dialog` in `$PATH` at startup ([`Compositor.cpp` in `hyprwm/Hyprland`](https://github.com/hyprwm/Hyprland/blob/main/src/Compositor.cpp)) and fires a 15-second notification overlay if missing. Upstream provides a specific config flag to suppress this check when the user knowingly omits the package:

```
misc {
    disable_hyprland_guiutils_check = true
}
```

We append this block to `UserConfigs/UserSettings.conf` during build so the warning never appears.

**Reference:** [`hyprwm/hyprland-qt-support` issue #9](https://github.com/hyprwm/hyprland-qt-support/issues/9) (Fedora 43 Qt6.10 dependency conflict, open). The same constraint affects [`cjuniorfox/hyprland-atomic`](https://github.com/cjuniorfox/hyprland-atomic) — their `build.sh` comments "removed hyprland-qtutils from Fedora 43 release because of compatibility issues". No F43 COPR currently ships a Qt6.10-compatible `hyprland-qt-support`. Revisit when upstream or solopasha rebuilds; once `hyprland-qtutils` becomes installable again, remove the `disable_hyprland_guiutils_check` block and add `hyprpolkitagent` + `hyprland-qtutils` back to the package list.

### Applying the skel to existing `$HOME`

`/etc/skel` only copies to `$HOME` for **newly created** user accounts. A user who rebased from a previous image already has `$HOME` and will not get the new skel on first boot. We ship a `ujust` recipe that rsyncs `/etc/skel/` into `$HOME`:

```sh
ujust sync-skel-config              # safe -- skips files that already exist in $HOME
ujust sync-skel-config overwrite=1  # clobber existing files with the new skel
```

The recipe lives in `files/usr/share/ublue-os/just/60-custom.just` — the `60-custom` filename is uBlue's sanctioned extension point: `base-main`'s `/usr/share/ublue-os/justfile` already contains `import? "/usr/share/ublue-os/just/60-custom.just"` (the `?` makes it optional, so plain base-main tolerates its absence).

### SDDM greeter — pre-baked at image build time

Two assets ship into the image for the greeter:

- **[`HyDE-Project/sddm-hyprland`](https://github.com/HyDE-Project/sddm-hyprland)** — Wayland-compositor integration that makes SDDM render through a Hyprland compositor. `make install PREFIX=/usr` drops `/usr/share/hypr/sddm/hyprland.conf` + `/etc/sddm.conf.d/sddm-hyprland.conf` (sets `CompositorCommand=Hyprland -c /usr/share/hypr/sddm/hyprland.conf`) + `/etc/sddm.conf.d/sddm-user.conf` (cursor fix). Qt6-compatible. Pinned to tag `v0.48.0`.
- **[`Keyitdev/sddm-astronaut-theme`](https://github.com/Keyitdev/sddm-astronaut-theme)** (2.7k stars, actively maintained) — SDDM theme. Cloned into `/usr/share/sddm/themes/sddm-astronaut-theme`, pinned to commit `d73842c` (no upstream tags exist). Fonts in the repo's `Fonts/` are copied to `/usr/share/fonts/`. We sed-patch the theme's `metadata.desktop` to point at the **`astronaut` variant** (the repo's namesake, space-themed); alternatives `black_hole`, `cyberpunk`, `japanese_aesthetic`, `purple_leaves`, etc. are a one-line build-arg change.

We also ship:
- `/etc/sddm.conf.d/theme.conf` with `[Theme] Current=sddm-astronaut-theme`
- `/etc/sddm.conf.d/virtualkbd.conf` with `[General] InputMethod=qtvirtualkeyboard` (astronaut theme needs `qt6-qtvirtualkeyboard`)
- `/etc/sddm.conf.d/backup_the_hyde_project.conf` (empty marker — legacy from the HyDE era; harmless, kept so any future HyDE reintroduction skips its own SDDM touches)

Previous iterations tried HyDE's `Sddm_Corners` theme (Qt5 — dropped with the Qt5 stack) and Fedora's `sddm-themes`/`maldives` (aesthetically underwhelming — *"insanely ugly"* per user testing). `sddm-breeze` was rejected because it drags `plasma-workspace` (~200-500 MB of KDE deps).

## Build & Release

### Files

```
Containerfile                  # two-stage: scratch ctx + base-main
Justfile                       # local-dev convenience recipes
build_files/
  build.sh                     # bind-mounted into the build, never lands in image
files/                         # filesystem overlay, COPY'd into final image
  etc/systemd/system/install-zen-browser.service
  etc/sddm.conf.d/theme.conf                      # selects sddm-astronaut-theme
  etc/sddm.conf.d/virtualkbd.conf                 # qtvirtualkeyboard (astronaut theme dep)
  etc/sddm.conf.d/backup_the_hyde_project.conf    # legacy marker (harmless)
  usr/bin/atomic-hyprland-dx-groups
  usr/lib/systemd/system/atomic-hyprland-dx-groups.service
  usr/lib/sysusers.d/atomic-hyprland.conf         # declares docker/incus-admin/libvirt
  usr/share/ublue-os/just/60-custom.just          # ujust sync-skel-config
.github/workflows/build.yml
README.md
DESIGN.md                      # this file
PLAN.md                        # implementation plan
```

The `files/` tree is `COPY files/ /` into the image in the Containerfile before `build.sh` runs.

### Containerfile (shape)

```dockerfile
ARG FEDORA_VERSION=43
FROM ghcr.io/ublue-os/base-main:${FEDORA_VERSION}

COPY files/ /
COPY build.sh /tmp/build.sh
RUN /tmp/build.sh && \
    ostree container commit
```

### `build.sh` responsibilities

Installer choice — we use `dnf5` inside the build (matching uBlue's own images) except for the two `rpm-ostree override remove` steps, which require `rpm-ostree` to record the override in the image metadata. Both paths work in a container build against an ostree base.

1. Enable `solopasha/hyprland` and `pgdev/ghostty` COPRs by curling their `.repo` files into `/etc/yum.repos.d/` (pattern from `cjuniorfox/hyprland-atomic`). Define a `copr_install_isolated` helper function (copied verbatim from `ublue-os/bluefin` → `build_files/shared/copr-helpers.sh`) for later use with `che/nerd-fonts`.
2. Install Microsoft VS Code repo file.
3. Install Docker CE repo file with the disable-then-`--enablerepo` pattern (see Container stack section).
4. `dnf5 -y install --setopt=install_weak_deps=False` the full package list. The weak-deps flag is a meaningful image-size win; `wayblueorg/wayblue` uses it, `cjuniorfox/hyprland-atomic` omits it.
5. `rpm-ostree override remove firefox firefox-langpacks` — `base-main` ships Firefox; we prefer the Flatpak version for an Atomic system.
6. `systemctl enable sddm.service`.
7. **SDDM greeter + theme + Hyprland-Dots rice.** In a single scratch dir:
   - Clone `HyDE-Project/sddm-hyprland` at pinned tag `v0.48.0`; `make install PREFIX=/usr`.
   - Clone `Keyitdev/sddm-astronaut-theme` into `/usr/share/sddm/themes/sddm-astronaut-theme`, `git reset --hard` to pinned commit `d73842c`, `rm -rf .git`. Copy `Fonts/*` → `/usr/share/fonts/`. Sed `metadata.desktop` → `ConfigFile=Themes/${SDDM_ASTRONAUT_VARIANT}.conf`.
   - Clone `LinuxBeginnings/Hyprland-Dots` unpinned (master, shallow). Copy `config/` → `/etc/skel/.config/`. Sed `$term = ghostty` into `01-UserDefaults.conf`. Append a `misc { disable_hyprland_guiutils_check = true }` block to `UserConfigs/UserSettings.conf`.
   - The static `theme.conf` + `virtualkbd.conf` + `backup_the_hyde_project.conf` are shipped via `files/etc/sddm.conf.d/`.
   See "SDDM greeter" and "Desktop Environment" sections above for full rationale.
8. Pre-add the Flathub remote system-wide so Flatpak installs work out of the box (`base-main` does not configure this):
   ```bash
   flatpak remote-add --if-not-exists --system flathub https://dl.flathub.org/repo/flathub.flatpakrepo
   ```
9. Enable automatic update timers to complete the "fully automatic updates" story alongside the inherited `rpm-ostreed-automatic.timer`:
   ```
   systemctl enable --global flatpak-user-update.timer
   systemctl enable flatpak-system-update.timer
   systemctl enable --global podman-auto-update.timer
   ```
10. `systemctl enable install-zen-browser.service` — first-boot Flatpak install of Zen Browser (see "Browser" below).
11. Leave the solopasha COPR `.repo` file in place so `rpm-ostree upgrade` continues to pull Hyprland updates between weekly CI rebuilds. The alternative (deleting the repo file post-install to pin Hyprland) is explicitly rejected: weekly CI already handles freshness, and live COPR updates match our "latest Hyprland" intent.

### Browser — Zen Browser via Flatpak

No browser is installed via RPM. `base-main`'s bundled Firefox is removed in build.sh step 5. The expected browser is [Zen Browser](https://zen-browser.app/) (`app.zen_browser.zen` on Flathub), a Firefox-based productivity browser popular in Hyprland rices.

First-boot installation is automated via a systemd oneshot unit shipped under `files/etc/systemd/system/install-zen-browser.service` and enabled in build.sh. The unit:

- runs once after `network-online.target`
- installs `app.zen_browser.zen` system-wide from the pre-configured Flathub remote
- touches `/var/lib/atomic-hyprland/zen-installed` as a run-once guard

Known trade-offs inherited from running a Flatpak browser (configs under `~/.var/app/app.zen_browser.zen/`, file access via `xdg-desktop-portal`, native-messaging hosts require sandbox overrides) are accepted. User does not use 1Password/KeepassXC desktop native-messaging integration, so the main Flatpak-browser papercut does not apply.

### CI (`build.yml`)

- **Triggers:** push to `main`, PRs, weekly schedule (`cron: "0 4 * * 1"`), manual `workflow_dispatch`.
- **Build:** `podman build` with `FEDORA_VERSION` build-arg.
- **Tags:**
  - On `main` push / schedule / manual: `:43`, `:latest`, `:43-<YYYYMMDD>`
  - On PR: `:pr-<number>` (does not touch `:43` or `:latest`)
- **Push:** GHCR (`ghcr.io/<gh-user>/atomic-hyprland`), using `GITHUB_TOKEN`.

### Tag strategy

- `:43` — what the running system tracks. Rebase once, stay here.
- `:latest` — alias of the current Fedora version. Convenience only.
- `:43-<YYYYMMDD>` — immutable daily snapshot for pinning or rollback to a specific day.
- `:pr-<N>` — PR previews, for rebasing-to-test before merging.

### Pinned vs unpinned upstream refs

Three upstream sources are cloned during build. Two are **pinned** (stable infra, we want predictability); one is **unpinned** (fast-moving rice, we want live updates).

```bash
# Pinned
SDDM_HYPRLAND_TAG="v0.48.0"            # HyDE-Project/sddm-hyprland
SDDM_ASTRONAUT_COMMIT="d73842c"        # Keyitdev/sddm-astronaut-theme
SDDM_ASTRONAUT_VARIANT="astronaut"

# Unpinned (tracks master via shallow clone each build)
# LinuxBeginnings/Hyprland-Dots
```

**Why the split:**

- SDDM greeter assets should not change visually under the user. Pinned = predictable.
- Hyprland-Dots evolves rapidly (new waybar modules, keybinds, scripts) and we WANT those updates automatically. Unpinning + weekly CI gives zero-maintenance auto-update.
- Fedora packages, solopasha COPR, ghostty COPR, Docker CE, `che/nerd-fonts` — all flow freely on every build too. Hyprland-Dots is consistent with that posture.

**Upgrade procedure for pinned refs:**

1. Open a PR editing the constants in `build.sh`.
2. CI builds `:pr-<N>`; rebase to it, verify the greeter still renders.
3. Merge; next `rpm-ostree upgrade` lands the update.

**Cadence for pinned refs:** manual, ad-hoc. Tag-bump automation (Renovate) is out of scope for v1.

**Cadence for Hyprland-Dots:** automatic via weekly CI — no action needed. After reboot, run `ujust sync-skel-config overwrite=1` if you want to pick up the new configs into `$HOME`.

## Upgrade Flow

1. **Initial rebase:**
   ```sh
   rpm-ostree rebase ostree-unverified-registry:ghcr.io/<gh-user>/atomic-hyprland:43
   systemctl reboot
   ```
2. **Automatic updates:** `rpm-ostreed-automatic.timer` (inherited from `base-main`) pulls the latest of `:43` nightly in the background. Reboot applies.
3. **Weekly CI rebuild** ensures Fedora security updates flow in even without code changes.
4. **Testing a change before merge:** build produces `:pr-<N>`; rebase to it, verify, then merge.
5. **Breakage recovery:** `rpm-ostree rollback && systemctl reboot` returns to the previous deployment.

## Update Workflow (`ujust update`)

`ujust update` is inherited from `base-main` (provided by `ublue-os-just`) and behaves identically to the way it does on Aurora / Bluefin / Bazzite. On this image it runs:

1. **`rpm-ostree upgrade`** — pulls the latest manifest of the currently-rebased tag. Because the system is rebased to `ostree-unverified-registry:ghcr.io/<gh-user>/atomic-hyprland:43`, this pulls the latest `:43` build from our GHCR. Weekly CI guarantees a fresh build is always available even when no code has changed.
2. **`flatpak update -y`** — updates user and system Flatpaks.
3. **`brew update && brew upgrade`** — Homebrew is inherited from `base-main`; update logic is inherited too.
4. **Firmware** via `fwupdmgr` if present.

The new deployment is staged; a reboot activates it. `rpm-ostree rollback && systemctl reboot` reverts to the previous deployment if anything goes wrong.

No behavioral change from Aurora beyond the `rpm-ostree` source — muscle memory transfers.

## Risks & Mitigations

- **Layered-package build failure on Fedora version bump** (most often VS Code): caught by weekly scheduled CI before it reaches the laptop.
- **HyDE upstream breaking changes:** HyDE's installer is run manually and versioned independently; a bad HyDE release does not brick the image.
- **solopasha COPR outage or package conflict:** falls back to rebuilding with Fedora-repo Hyprland as a short-term patch.
- **Unsigned image tampering:** accepted risk. Mitigation is GitHub account hygiene (2FA, recovery codes). An attacker with GitHub push access could inject a malicious build; `rpm-ostree rollback` recovers post-hoc. Adding cosign signing later is a non-breaking change if this becomes a concern.

## Out of Scope (YAGNI)

Deliberately not in v1:

- cosign signing and signed rebase
- Custom `ujust` wrapper commands
- First-boot MOTD / welcome script
- `/etc/skel` dotfile vendoring
- Custom "Learn" keybind cheatsheet (HyDE ships one)
- Installable ISO via `bootc-image-builder`
- Nvidia variant
- Multi-Fedora-version matrix
- Virtualization opt-in toggle

Any of these can be added later without restructuring the image.
