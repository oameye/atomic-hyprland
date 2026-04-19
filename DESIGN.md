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
| `files/usr/bin/atomic-hyprland-dx-groups` | `ublue-os/bluefin` → `system_files/dx/usr/bin/bluefin-dx-groups` |
| `files/usr/lib/systemd/system/atomic-hyprland-dx-groups.service` | `ublue-os/bluefin` → `system_files/dx/usr/lib/systemd/system/bluefin-dx-groups.service` |
| SDDM greeter integration | `HyDE-Project/sddm-hyprland` (tracked by upstream tag, `make install`-ed at build time) |

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

## Desktop Environment (HyDE)

HyDE is **not** baked into the image. After rebasing, the user runs HyDE's upstream installer once:

```sh
bash <(curl -s https://raw.githubusercontent.com/HyDE-Project/HyDE/master/Scripts/install.sh)
```

Rationale: HyDE's installer is designed to run against a live `$HOME`, manages its own theme-switcher state, and pulls updates from its own repo. Vendoring a subset into `/etc/skel` would diverge from upstream and break the theme switcher. Since this is a personal image, running the installer once by hand is simpler than wrapping it.

**Ghostty theming:** HyDE's main repo defaults to kitty and its theme switcher themes kitty directly. Ghostty theming lives in the sidecar repo [`HyDE-Project/terminal-emulators`](https://github.com/HyDE-Project/terminal-emulators). After HyDE's installer runs, clone that repo and copy `ghostty/` into `~/.config/ghostty/`; the theme switcher will then keep ghostty in sync on theme changes.

### SDDM greeter — pre-baked at image build time

[`HyDE-Project/sddm-hyprland`](https://github.com/HyDE-Project/sddm-hyprland) writes to `/usr/share/` at install time. On rpm-ostree Atomic, `/usr/` is a read-only ostree tree — post-boot writes fail or don't persist. We therefore pre-bake at image build time:

1. Install the Qt6 session/greeter stack and `sddm-themes` (see "Session / greeter" above).
2. Clone `HyDE-Project/sddm-hyprland` at the pinned tag (currently `v0.48.0`) in `build.sh` and run `make install PREFIX=/usr`. This drops:
   - `/usr/share/hypr/sddm/hyprland.conf`, `/usr/share/hypr/sddm/hyprprefs.conf`
   - `/etc/sddm.conf.d/sddm-hyprland.conf` (sets `CompositorCommand=Hyprland -c /usr/share/hypr/sddm/hyprland.conf`)
   - `/etc/sddm.conf.d/sddm-user.conf` (cursor fix)
3. Ship `/etc/sddm.conf.d/theme.conf` with `[Theme] Current=maldives` selecting the theme shipped by the Fedora `sddm-themes` package.
4. Ship an empty marker file `/etc/sddm.conf.d/backup_the_hyde_project.conf`. HyDE's `install_pst.sh` tests for this file and skips its own SDDM reconfiguration when present — preventing the user's post-rebase HyDE installer from attempting (and failing on) `/usr/share/sddm/themes/` writes to extract HyDE's Qt5-based themes.

Result: the greeter renders through Hyprland as a Wayland compositor with Fedora's `maldives` SDDM theme, everything baked into the image, zero runtime `/usr/` writes, zero manual SDDM steps for the user.

**Why not HyDE's Candy/Corners themes?** They use Qt5 QML imports (`QtQuick 2.12`, `QtGraphicalEffects 1.12`, etc.). Fedora 43 ships SDDM built against Qt6 and we deliberately exclude the Qt5 runtime. `sddm-themes`/`maldives` is what wayblue ships on its Hyprland variant and is KDE-dependency-free (unlike `sddm-breeze`, which drags `plasma-workspace`).

## Build & Release

### Files

```
Containerfile
build.sh
files/
  etc/systemd/system/install-zen-browser.service
  etc/sddm.conf.d/theme.conf                    # selects maldives
  etc/sddm.conf.d/backup_the_hyde_project.conf  # marker -- skips HyDE's SDDM step
  usr/bin/atomic-hyprland-dx-groups
  usr/lib/systemd/system/atomic-hyprland-dx-groups.service
.github/workflows/build.yml
README.md
DESIGN.md            # this file
PLAN.md              # implementation plan
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
7. Clone `HyDE-Project/sddm-hyprland` at pinned tag `v0.48.0` and run `make install PREFIX=/usr`. The `theme.conf` + `backup_the_hyde_project.conf` marker files are shipped via `files/etc/sddm.conf.d/`. See the "SDDM greeter" section above for rationale. Tag is bumped by PR so image builds are reproducible.
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

### Pinned upstream tags — what they mean and how to upgrade them

One upstream asset is pinned by tag in `build.sh`:

```bash
SDDM_HYPRLAND_TAG="v0.48.0"   # HyDE-Project/sddm-hyprland — make install-ed at build time
```

This pin exists for **reproducibility of the SDDM Wayland-compositor integration**. Everything else flows freely:

- All Fedora / solopasha / ghostty / VS Code / Docker / nerd-fonts packages track their repos on every build.
- HyDE's user-side installer (run post-rebase) hits `master` — not pinned.
- Weekly CI picks up all security and package updates regardless of the pin.

**Upgrade procedure:**

1. Open a PR editing the tag string in `build.sh`.
2. CI builds `:pr-<N>`; rebase to it, verify the greeter renders.
3. Merge; `:43` updates on next build; next `rpm-ostree upgrade` lands it.

**Cadence:** manual, ad-hoc. The integration churns slowly and there is no security urgency. Tag-bump automation (Renovate or a custom "check releases" workflow) is out of scope for v1.

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
