# CLAUDE.md

## What is this project?

A personal Fedora Atomic desktop image built on Universal Blue's `base-main`, shipping Hyprland with LinuxBeginnings/Hyprland-Dots baked in. Single-user, AMD GPU, no Nvidia variant.

## Key files

- `Containerfile` — two-stage OCI build (scratch context + base-main)
- `build_files/build.sh` — all build logic (bind-mounted, never in final image)
- `files/` — static filesystem overlay (systemd units, SDDM configs, ujust recipes)
- `DESIGN.md` — architectural decisions and upstream attribution
- `.github/workflows/build.yml` — CI/CD (weekly + push + PR)

## Build & test

```sh
just build          # podman build the image locally
just lint           # shellcheck all .sh files
just format         # shfmt all .sh files
```

There are no unit tests. The build itself is the test — if `build.sh` exits non-zero or `bootc container lint` fails, CI catches it.

## build.sh structure

The script has 10 numbered sections. Keep section numbers in comments when editing:

1. Enable live COPRs (pgdev/ghostty, errornointernet/quickshell)
2. VS Code repo
3. Docker CE repo (disabled by default)
4. Main `dnf5 install` + isolated COPR installs (nerd-fonts, bazaar/uupd, wallust)
5. Remove Firefox
6. Source builds (hyprland-guiutils via CMake, awww via Cargo)
7. SDDM greeter + theme + Hyprland-Dots into `/etc/skel`
8. Flathub remote
9. Enable systemd units
10. Cleanup (`dnf5 clean all`, purge `/var/cache`, `/tmp`)

## Conventions

- **Bash:** `set -euo pipefail`. Use `|| true` only for tolerable failures (e.g., Firefox removal). UPPERCASE for constants/pinned tags, lowercase for locals.
- **Packages:** always `--setopt=install_weak_deps=False`. Group by purpose with comments.
- **COPRs left enabled** (pgdev/ghostty, errornointernet/quickshell, VS Code, Docker CE) vs **isolated** (che/nerd-fonts, ublue-os/packages, errornointernet/packages). Isolated COPRs must use `copr_install_isolated` so no `.repo` survives.
- **Pinned refs** (SDDM, source builds) use `*_TAG`/`*_COMMIT` variables at the top of build.sh. Hyprland-Dots is unpinned (tracks master).
- **Systemd units** use `atomic-hyprland-` prefix.
- **Static overlay files** go in `files/` mirroring the filesystem root.
- **justfile variables** use `overwrite := "0"` syntax (not recipe parameters) so `ujust recipe key=value` works.

## Adding a package

1. Add to the `PACKAGES=()` array in `build.sh` section 4, in the appropriate category block.
2. If the package is in a new COPR that should stay enabled, add it to the loop in section 1.
3. If the package is in a COPR that should NOT stay enabled, use `copr_install_isolated`.
4. If the package isn't in any repo, add a source-build block in section 6 with a pinned tag variable at the top.

## Adding a Flatpak

Drop a `.preinstall` file in `files/usr/share/flatpak/preinstall.d/`. The existing `flatpak-preinstall.service` picks it up on first boot.

## Hyprland-Dots overrides

Baked-in overrides are sed patches in section 7b of build.sh. Currently:
- `$term = ghostty` (upstream default: kitty)
- `$files = nautilus` (upstream default: thunar)

Do not append config blocks to UserSettings.conf unless absolutely necessary — prefer sed patches on existing variables.

## Source builds

The entire Hyprland ecosystem is source-built in `build.sh` section 6. All use the shared `cmake_build_install` helper and are pinned via `*_TAG` variables at the top of `build.sh`.

**Core libs** (build order): **hyprwayland-scanner** → **hyprutils** → **hyprlang** → **hyprcursor** → **hyprgraphics** → **aquamarine**

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
