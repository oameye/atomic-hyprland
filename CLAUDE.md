# CLAUDE.md

## What is this project?

A personal Fedora Atomic desktop image built for one machine: AMD GPU, Fedora 43, single user. It ships Hyprland with basecamp/omarchy baked in. It is not designed to be general-purpose — assumptions about GPU, hardware, and workflow are hard-coded throughout.

## Key files

- `Containerfile` — two-stage OCI build (scratch context + base-main)
- `build_files/build.sh` — layer 2 entry point: packages, desktop setup, Flathub/systemd/cleanup
- `build_files/repos.sh` — COPR/repo setup + `copr_install_isolated` helper
- `build_files/packages.sh` — all dnf5 package installs
- `build_files/source-builds.sh` — layer 1 entry point: repos + full Hyprland ecosystem + non-hyprwm source builds
- `build_files/desktop.sh` — SDDM greeter + omarchy into `/etc/skel`
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

The build is split into two layers. `source-builds.sh` runs first for repos + source-built binaries, then `build.sh` handles packages, desktop setup, Flathub, systemd units, and cleanup. Source-build pins live in `source-builds.sh`; layer-2 metadata pins live in `build.sh`.

| File | Responsibility |
|---|---|
| `build.sh` | Layer 2 entry point, desktop setup, Flathub/systemd/cleanup |
| `repos.sh` | COPR enablement, VS Code repo, Docker CE repo, `copr_install_isolated` helper |
| `packages.sh` | `dnf5 install`, isolated COPR installs, Firefox removal |
| `source-builds.sh` | Layer 1 entry point, repo setup, all source builds + `cmake_build_install` / `cargo_install` helpers |
| `desktop.sh` | SDDM greeter + theme + omarchy into `/etc/skel` |

## Conventions

- **Bash:** `set -euo pipefail`. Use `|| true` only for tolerable failures (e.g., Firefox removal). UPPERCASE for constants/pinned tags, lowercase for locals.
- **Packages:** always `--setopt=install_weak_deps=False`. Group by purpose with comments.
- **Repos left enabled** (brycensranch/gpu-screen-recorder-git, VS Code, Docker CE) vs **isolated COPRs** (che/nerd-fonts, ublue-os/packages, erikreider/swayosd). Isolated COPRs must use `copr_install_isolated` so no `.repo` survives.
- **Pinned refs** use `*_TAG`/`*_COMMIT` variables near the top of the layer that consumes them. Source-build pins live in `source-builds.sh`; Omarchy is pinned via `OMARCHY_REF` in `build.sh`.
- **Systemd units** use `atomic-hyprland-` prefix.
- **Static overlay files** go in `files/` mirroring the filesystem root.
- **justfile user-tunable knobs** use module-level `key := "0"` assignments and are overridden from the CLI as `ujust key=value recipe` (the override must precede the recipe name — that's how `just` parses its command line). Do *not* use recipe parameters for this: `just` has no named-parameter CLI syntax, so `ujust recipe key=value` silently passes the literal string `"key=value"` as the positional value instead of setting the parameter.

## Adding a package

1. Add to `PACKAGES=()` in `packages.sh`, in the appropriate category block.
2. If the package is in a new COPR that should stay enabled, add it to the loop in `repos.sh`.
3. If the package is in a COPR that should NOT stay enabled, call `copr_install_isolated` in `packages.sh`.
4. If the package isn't in any repo, add a source-build block in `source-builds.sh` with a pinned tag in `source-builds.sh`.

## Adding a Flatpak

Drop a `.preinstall` file in `files/usr/share/flatpak/preinstall.d/`. The existing `flatpak-preinstall.service` helper installs it on first boot.

## Omarchy overrides

Arch-specific bits are stripped out at build time rather than sed-patched:

- All `omarchy-install-*`, `omarchy-pkg-*`, `omarchy-webapp-*`, `omarchy-tui-*`, and `omarchy-windows-*` scripts are deleted from skel. The image ships apps via Flatpak/COPR/brew, not pacman/yay.
- The "Install" entry is sed-stripped from the top-level `omarchy-menu` (both the menu string and the case handler).
- `omarchy-update` is overwritten with a one-line stub that calls `ujust update` (which handles bootc + flatpak + brew).
- `JetBrainsMono Nerd Font` (omarchy upstream default) is source-installed from the `ryanoasis/nerd-fonts` release in `source-builds.sh`; `files/etc/fonts/conf.d/80-atomic-hyprland-monospace.conf` pins the `monospace` fontconfig alias so walker and other generic-alias consumers resolve correctly.

Default Hyprland theme is `tokyo-night`, bootstrapped at build time as a real directory at `/etc/skel/.config/omarchy/current/theme/` (via `omarchy-theme-set-templates` rendering + atomic `mv` into place — no symlink).

Do not patch config/ files unless the change cannot be done by the user after first login.

## Source builds

The entire Hyprland ecosystem is source-built in `source-builds.sh`. Helpers `cmake_build_install` and `cargo_install` reduce repetition. Source-build tags are pinned at the top of `source-builds.sh`.

**Core libs** (build order): **hyprwayland-scanner** → **hyprutils** → **hyprlang** → **hyprcursor** → **hyprgraphics** → **aquamarine** → **hyprwire** → **hyprland-protocols** (meson) → **glaze**

**Compositor**: **hyprland** (CMake, uses `--recurse-submodules` for bundled udis86 + hyprland-protocols)

**Toolkit**: **hyprtoolkit** → **hyprland-guiutils** (Wayland-native, no Qt6)

**Satellite tools**: **hyprlock**, **hypridle**, **hyprpicker**, **hyprsunset**, **xdg-desktop-portal-hyprland**

**Non-hyprwm desktop tools** (all source-built):
- **satty** (Cargo + GTK4) — screenshot annotation
- **hyprshot** (curl shell script) — screenshot helper
- **cliphist** (Go) — clipboard history
- **gum** (Go) — interactive prompts/confirms used by omarchy-menu, omarchy-migrate
- **uwsm** (Python/meson) — Wayland session manager

**Qt6 components**: **hyprland-qt-support** (QML style plugin) + **hyprpolkitagent** (polkit agent) — built against system Qt6.10.
