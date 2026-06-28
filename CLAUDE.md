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

The build is split into two layers. `source-builds.sh` runs first for repos + source-built binaries, then `build.sh` handles packages, desktop setup, Flathub, systemd units, and cleanup. All pinned refs (source-build tags, the Hyprland COPR name, Omarchy ref) live in `pins.sh`, which both layers source.

| File | Responsibility |
|---|---|
| `build.sh` | Layer 2 entry point, desktop setup, Flathub/systemd/cleanup |
| `repos.sh` | COPR enablement, VS Code repo, Docker CE repo, `copr_install_isolated` helper |
| `packages.sh` | `dnf5 install`, isolated COPR installs, Firefox removal |
| `source-builds.sh` | Layer 1 entry point, repo setup, non-hyprwm source builds + `cargo_install` helper |
| `desktop.sh` | SDDM greeter + theme + omarchy into `/etc/skel` |

## Conventions

- **Bash:** `set -euo pipefail`. Use `|| true` only for tolerable failures (e.g., Firefox removal). UPPERCASE for constants/pinned tags, lowercase for locals.
- **Packages:** always `--setopt=install_weak_deps=False`. Group by purpose with comments.
- **Repos left enabled** (brycensranch/gpu-screen-recorder-git, VS Code, Docker CE) vs **isolated COPRs** (che/nerd-fonts, ublue-os/packages, erikreider/swayosd). Isolated COPRs must use `copr_install_isolated` so no `.repo` survives.
- **Pinned refs** use `*_TAG`/`*_COMMIT`/`*_REF` variables in `pins.sh` (sourced by both layers). The hyprwm ecosystem has no tags to pin; it comes from the COPR named in `HYPRLAND_COPR`.
- **Systemd units** use `atomic-hyprland-` prefix.
- **Static overlay files** go in `files/` mirroring the filesystem root.
- **justfile user-tunable knobs** use module-level `key := "0"` assignments and are overridden from the CLI as `ujust key=value recipe` (the override must precede the recipe name — that's how `just` parses its command line). Do *not* use recipe parameters for this: `just` has no named-parameter CLI syntax, so `ujust recipe key=value` silently passes the literal string `"key=value"` as the positional value instead of setting the parameter.

## Adding a package

1. Add to `PACKAGES=()` in `packages.sh`, in the appropriate category block.
2. If the package is in a new COPR that should stay enabled, add it to the loop in `repos.sh`.
3. If the package is in a COPR that should NOT stay enabled, call `copr_install_isolated` in `packages.sh`.
4. If the package isn't in any repo, add a source-build block in `source-builds.sh` with a pinned tag in `pins.sh`.

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

## Hyprland ecosystem (COPR)

The entire hyprwm ecosystem is installed from the `craftidore/wayblueorg-hyprland` COPR (the same COPR the wayblue project uses), not source-built. The COPR name is pinned as `HYPRLAND_COPR` in `pins.sh` and installed via `copr_install_isolated` in `packages.sh`. Installing the compositor + satellites pulls the hypr* libraries (hyprutils, hyprlang, hyprcursor, hyprgraphics, aquamarine, hyprwire, hyprland-protocols, glaze) as dependencies in the same transaction.

Installed set: **hyprland-git** (compositor), **hyprlock**, **hypridle**, **hyprpicker**, **hyprsunset**, **xdg-desktop-portal-hyprland**, **hyprtoolkit**, **hyprland-guiutils**, **hyprland-qt-support**, **hyprpolkitagent**.

Caveats to know:
- The COPR ships Hyprland **only** as a rolling git build (`hyprland-git`). There is no stable `hyprland` RPM for Fedora anywhere, and Fedora's own repos lack most of the stack (and ship the few libs they do have far too old). So Hyprland tracks git master, rebuilt by the COPR maintainer every other Saturday. Omarchy's hyprland config may need fixes when upstream renames/deprecates options.
- The expected binary paths are asserted in `verify.sh` via `PACKAGED_HYPRWM_EXECUTABLES` in `manifest.sh`. If the COPR changes a binary's install path, that check catches it.

## Source builds

Only the non-hyprwm tools that have no usable Fedora/COPR package are source-built in `source-builds.sh`. The `cargo_install` helper reduces repetition; `BUILD_DEPS` is scoped to exactly these builds.

- **walker** (Cargo + GTK4) + **hyprland-preview-share-picker** (Cargo + GTK4/gtk4-layer-shell) screen-share picker
- **wiremix** (Cargo + PipeWire, bindgen needs `clang-devel`) audio mixer TUI
- **elephant** (Go, + provider `.so` plugins built with the matching toolchain) walker data provider
- **uwsm** (meson) Wayland session manager
- **xdg-terminal-exec** + **hyprshot** (shell scripts)
- **JetBrainsMono Nerd Font** (upstream release tarball)

Other tools (satty, cliphist, gum, starship, impala, bluetui) are installed as pinned upstream release binaries/RPMs in `packages.sh`, not source-built.
