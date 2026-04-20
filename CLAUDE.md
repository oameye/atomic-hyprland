# CLAUDE.md

## What is this project?

A personal Fedora Atomic desktop image built for one machine: AMD GPU, Fedora 43, single user. It ships Hyprland with LinuxBeginnings/Hyprland-Dots baked in. It is not designed to be general-purpose — assumptions about GPU, hardware, and workflow are hard-coded throughout.

## Key files

- `Containerfile` — two-stage OCI build (scratch context + base-main)
- `build_files/build.sh` — entry point: pinned tags, sources sub-scripts, handles Flathub/systemd/cleanup
- `build_files/repos.sh` — COPR/repo setup + `copr_install_isolated` helper
- `build_files/packages.sh` — all dnf5 package installs
- `build_files/source-builds.sh` — full Hyprland ecosystem + non-hyprwm source builds
- `build_files/desktop.sh` — SDDM greeter + Hyprland-Dots into `/etc/skel`
- `files/` — static filesystem overlay (systemd units, SDDM configs, ujust recipes)
- `DESIGN.md` — architecture and design decisions
- `.github/workflows/build.yml` — CI/CD (weekly + push + PR)

## Build & test

```sh
just build          # podman build the image locally
just lint           # shellcheck all .sh files
just format         # shfmt all .sh files
```

There are no unit tests. The build itself is the test — if `build.sh` exits non-zero or `bootc container lint` fails, CI catches it.

## build_files structure

`build.sh` sources the other scripts in order, then handles Flathub, systemd units, and cleanup inline. All pinned tags live at the top of `build.sh`.

| File | Responsibility |
|---|---|
| `build.sh` | Entry point, pinned tags, orchestration |
| `repos.sh` | COPR enablement, VS Code repo, Docker CE repo, `copr_install_isolated` helper |
| `packages.sh` | `dnf5 install`, isolated COPR installs, Firefox removal |
| `source-builds.sh` | All source builds + `cmake_build_install` / `cargo_install` helpers |
| `desktop.sh` | SDDM greeter + theme + Hyprland-Dots into `/etc/skel` |

## Conventions

- **Bash:** `set -euo pipefail`. Use `|| true` only for tolerable failures (e.g., Firefox removal). UPPERCASE for constants/pinned tags, lowercase for locals.
- **Packages:** always `--setopt=install_weak_deps=False`. Group by purpose with comments.
- **COPRs left enabled** (pgdev/ghostty, errornointernet/quickshell, VS Code, Docker CE) vs **isolated** (che/nerd-fonts, ublue-os/packages, errornointernet/packages). Isolated COPRs must use `copr_install_isolated` so no `.repo` survives.
- **Pinned refs** (SDDM, source builds) use `*_TAG`/`*_COMMIT` variables at the top of build.sh. Hyprland-Dots is unpinned (tracks master).
- **Systemd units** use `atomic-hyprland-` prefix.
- **Static overlay files** go in `files/` mirroring the filesystem root.
- **justfile variables** use `overwrite := "0"` syntax (not recipe parameters) so `ujust recipe key=value` works.

## Adding a package

1. Add to `PACKAGES=()` in `packages.sh`, in the appropriate category block.
2. If the package is in a new COPR that should stay enabled, add it to the loop in `repos.sh`.
3. If the package is in a COPR that should NOT stay enabled, call `copr_install_isolated` in `packages.sh`.
4. If the package isn't in any repo, add a source-build block in `source-builds.sh` with a pinned tag in `build.sh`.

## Adding a Flatpak

Drop a `.preinstall` file in `files/usr/share/flatpak/preinstall.d/`. The existing `flatpak-preinstall.service` picks it up on first boot.

## Hyprland-Dots overrides

Baked-in overrides are sed patches in `desktop.sh`. Currently:
- `$term = ghostty` (upstream default: kitty)
- `$files = nautilus` (upstream default: thunar)

Do not append config blocks to UserSettings.conf unless absolutely necessary — prefer sed patches on existing variables.

## Source builds

The entire Hyprland ecosystem is source-built in `source-builds.sh`. Helpers `cmake_build_install` and `cargo_install` reduce repetition. All tags are pinned at the top of `build.sh`.

**Core libs** (build order): **hyprwayland-scanner** → **hyprutils** → **hyprlang** → **hyprcursor** → **hyprgraphics** → **aquamarine** → **hyprwire** → **hyprland-protocols** (meson) → **glaze**

**Compositor**: **hyprland** (CMake, uses `--recurse-submodules` for bundled udis86 + hyprland-protocols)

**Toolkit**: **hyprtoolkit** → **hyprland-guiutils** (Wayland-native, no Qt6)

**Satellite tools**: **hyprlock**, **hypridle**, **hyprpaper**, **hyprpicker**, **hyprsunset**, **xdg-desktop-portal-hyprland**

**Non-hyprwm desktop tools** (all source-built):
- **awww** (Cargo) — preferred wallpaper daemon
- **swww** (Cargo) — animated wallpaper fallback
- **satty** (Cargo + GTK4) — screenshot annotation
- **hyprshot** (curl shell script) — screenshot helper
- **cliphist** (Go) — clipboard history
- **nwg-look** (Go + GTK3) — GTK settings GUI
- **uwsm** (Python/meson) — Wayland session manager

**Qt6 components**: **hyprland-qt-support** (QML style plugin) + **hyprpolkitagent** (polkit agent) — built against system Qt6.10.
