#!/usr/bin/env bash
set -euo pipefail

WORK=$(mktemp -d)

# ── Omarchy ──────────────────────────────────────────────────────────
git clone --depth 1 --branch "${OMARCHY_REF}" --single-branch \
    https://github.com/basecamp/omarchy.git \
    "${WORK}/omarchy"
OMARCHY_COMMIT="$(git -C "${WORK}/omarchy" rev-parse HEAD)"

SKEL_OMARCHY=/etc/skel/.local/share/omarchy

require_upstream_literal() {
    local file="$1"
    local needle="$2"
    local description="$3"

    if ! grep -Fq "$needle" "$file"; then
        echo "Expected upstream ${description} in ${file} at ${OMARCHY_REF} (${OMARCHY_COMMIT}), but it was not found." >&2
        exit 1
    fi
}

# Layer 1: user dotfiles
mkdir -p /etc/skel/.config
cp -a "${WORK}/omarchy/config/." /etc/skel/.config/

# Desktop image — no battery. Upstream ships a per-user battery monitor
# service/timer via config/systemd/user/; drop them from skel so no user
# ends up with a unit that polls a non-existent battery.
rm -f /etc/skel/.config/systemd/user/omarchy-battery-monitor.service \
      /etc/skel/.config/systemd/user/omarchy-battery-monitor.timer

# Layer 2: omarchy system layer. Upstream layout is `$OMARCHY_PATH/{default,themes,bin}`
# where $OMARCHY_PATH resolves to ~/.local/share/omarchy (set by config/uwsm/env and
# default/bash/envs). Matching this layout lets every `omarchy-*` script find siblings
# and templates without patching.
mkdir -p "${SKEL_OMARCHY}"
cp -a "${WORK}/omarchy/default" "${SKEL_OMARCHY}/default"
cp -a "${WORK}/omarchy/themes"  "${SKEL_OMARCHY}/themes"
cp -a "${WORK}/omarchy/bin"     "${SKEL_OMARCHY}/bin"
chmod +x "${SKEL_OMARCHY}/bin/"*

# Strip install-related scripts — Arch package names don't map to Fedora and
# the image ships apps via Flatpak/COPR/brew instead.
rm -f "${SKEL_OMARCHY}/bin/"omarchy-install-* \
      "${SKEL_OMARCHY}/bin/"omarchy-pkg-* \
      "${SKEL_OMARCHY}/bin/"omarchy-webapp-* \
      "${SKEL_OMARCHY}/bin/"omarchy-tui-* \
      "${SKEL_OMARCHY}/bin/"omarchy-windows-*

# Strip pacman-only lifecycle scripts. These are orphaned on our image —
# the Update menu entry now bottoms out at `ujust update` (which handles
# bootc + flatpak + brew) and never reaches these internal helpers.
# Channel switching and version-channel display are meaningless when the
# image ships a pinned Omarchy ref and upgrades deliberately via PR.
rm -f "${SKEL_OMARCHY}/bin/"omarchy-refresh-pacman \
      "${SKEL_OMARCHY}/bin/"omarchy-channel-set \
      "${SKEL_OMARCHY}/bin/"omarchy-update-system-pkgs \
      "${SKEL_OMARCHY}/bin/"omarchy-update-aur-pkgs \
      "${SKEL_OMARCHY}/bin/"omarchy-update-keyring \
      "${SKEL_OMARCHY}/bin/"omarchy-update-orphan-pkgs \
      "${SKEL_OMARCHY}/bin/"omarchy-reinstall-pkgs \
      "${SKEL_OMARCHY}/bin/"omarchy-version-channel \
      "${SKEL_OMARCHY}/bin/"omarchy-version-pkgs

# Make the remaining Setup/Remove scripts tolerate failed pacman removals
# (their "clean up the old Arch package first" step is a no-op on Fedora;
# the rest of the script — udev rules, pam config, systemd enables — still
# does useful work).
# Match both `pacman -Rns ...` (as in omarchy-remove-dev-env) and
# `sudo pacman -Rns ...` (as in omarchy-setup-fido2 and -fingerprint).
sed -i 's/^\(\s*\(sudo[[:space:]]\+\)\?pacman -Rns\b.*\)$/\1 || true/' \
    "${SKEL_OMARCHY}/bin/omarchy-remove-dev-env" \
    "${SKEL_OMARCHY}/bin/omarchy-setup-fido2" \
    "${SKEL_OMARCHY}/bin/omarchy-setup-fingerprint"

# omarchy-debug and omarchy-upload-log list installed packages via
# `expac` / `pacman -Q`. Replace both with `rpm -qa | sort` so the debug
# bundle is complete on Fedora. The `$(...)` / `|` chars belong to the
# target script, not this shell — single quotes keep them literal.
#
# The omarchy-debug package-list line is a complex `$({ … } | sort)` block
# with nested `$(pacman -Qqe)` command substitutions, so a `[^)]+` class
# is too greedy-short. Match the whole line on the leading `expac` token
# instead and replace wholesale with `$(rpm -qa | sort)`.
# shellcheck disable=SC2016
sed -i -E \
    's#^\$\(\{ expac.*\| sort\)$#$(rpm -qa | sort)#' \
    "${SKEL_OMARCHY}/bin/omarchy-debug"
# shellcheck disable=SC2016
sed -i 's|pacman -Q 2>/dev/null \|\| echo "Failed to get package list"|rpm -qa \| sort|' \
    "${SKEL_OMARCHY}/bin/omarchy-upload-log"

# omarchy-theme-set-browser still targets the supported Linux managed-policy
# path under /etc/chromium/policies/managed, but we only keep the Chromium
# branch because Brave is not shipped on this image.
cat > "${SKEL_OMARCHY}/bin/omarchy-theme-set-browser" <<'EOF'
#!/usr/bin/env bash
# Apply the current omarchy theme's accent color to Chromium via its
# managed-policy file. Silently exits if chromium isn't on PATH.

omarchy-cmd-present chromium || exit 0

chromium_theme=~/.config/omarchy/current/theme/chromium.theme
policy_dir=/etc/chromium/policies/managed

if [[ -f $chromium_theme ]]; then
    rgb=$(<"$chromium_theme")
    # shellcheck disable=SC2086
    hex=$(printf '#%02x%02x%02x' ${rgb//,/ })
else
    hex="#1c2027"
fi

printf '{"BrowserThemeColor": "%s", "BrowserColorScheme": "device"}\n' "$hex" \
    > "$policy_dir/color.json"

chromium --refresh-platform-policy --no-startup-window >/dev/null 2>&1 || true
EOF
chmod +x "${SKEL_OMARCHY}/bin/omarchy-theme-set-browser"

# omarchy-launch-webapp upstream reads Exec= from host chromium.desktop to
# resolve the PWA launcher. chromium is a Flatpak on this image and its
# .desktop lives in /var/lib/flatpak/exports/share/applications/ — a path
# the upstream sed lookup does not check, so Exec= comes back empty and
# the exec line runs with no command. Go directly to the Flatpak instead;
# the --user-data-dir + managed-policy bridges still apply via the Flatpak
# override + /etc/chromium/policies/managed configured in build.sh.
cat > "${SKEL_OMARCHY}/bin/omarchy-launch-webapp" <<'EOF'
#!/usr/bin/env bash
# Launch a URL as a standalone web app via Flatpak Chromium's --app mode.
exec setsid uwsm-app -- flatpak run org.chromium.Chromium --app="$1" "${@:2}"
EOF
chmod +x "${SKEL_OMARCHY}/bin/omarchy-launch-webapp"

# omarchy-theme-set-obsidian upstream reads ~/.config/obsidian/obsidian.json
# for the list of vault paths; Flatpak Obsidian keeps that sandboxed under
# ~/.var/app/md.obsidian.Obsidian/config/obsidian/. Flathub's manifest grants
# --filesystem=home, so the vault paths stored inside resolve on the host
# unchanged — just the config location shifts.
cat > "${SKEL_OMARCHY}/bin/omarchy-theme-set-obsidian" <<'EOF'
#!/usr/bin/env bash
# Sync Omarchy theme to all Obsidian vaults registered with Flatpak Obsidian.

CURRENT_THEME_DIR="$HOME/.config/omarchy/current/theme"
OBSIDIAN_CONFIG="$HOME/.var/app/md.obsidian.Obsidian/config/obsidian/obsidian.json"

[[ -f $CURRENT_THEME_DIR/obsidian.css ]] || exit 0
[[ -f $OBSIDIAN_CONFIG ]] || exit 0

jq -r '.vaults | values[].path' "$OBSIDIAN_CONFIG" 2>/dev/null | while read -r vault_path; do
    [[ -d $vault_path/.obsidian ]] || continue

    theme_dir="$vault_path/.obsidian/themes/Omarchy"
    mkdir -p "$theme_dir"

    [[ -f $theme_dir/manifest.json ]] || cat > "$theme_dir/manifest.json" <<'MANIFEST'
{
  "name": "Omarchy",
  "version": "1.0.0",
  "minAppVersion": "0.16.0",
  "description": "Automatically syncs with your current Omarchy system theme colors and fonts",
  "author": "Omarchy",
  "authorUrl": "https://omarchy.org"
}
MANIFEST

    cp "$CURRENT_THEME_DIR/obsidian.css" "$theme_dir/theme.css"
done
EOF
chmod +x "${SKEL_OMARCHY}/bin/omarchy-theme-set-obsidian"

# Strip menu entries that lead to deleted scripts:
#   - "Install" top-level entry → show_install_menu (Install scripts deleted).
#     Upstream's go_to_menu lowercases input via ${1,,} so the case label is
#     *install*) (lowercase) — not *Install*).
#   - "Channel" entry in the Update submenu → show_update_channel_menu, which
#     invokes the deleted omarchy-channel-set. show_update_menu does not
#     lowercase its input, so the label stays *Channel*).
require_upstream_literal \
    "${SKEL_OMARCHY}/bin/omarchy-menu" \
    '󰉉  Install\n' \
    'omarchy-menu Install entry'
require_upstream_literal \
    "${SKEL_OMARCHY}/bin/omarchy-menu" \
    '󰔫  Channel\n' \
    'omarchy-menu Update > Channel entry'
sed -i \
    -e 's|󰉉  Install\\n||' \
    -e '/\*install\*)/d' \
    -e 's|󰔫  Channel\\n||' \
    -e '/\*Channel\*) show_update_channel_menu/d' \
    "${SKEL_OMARCHY}/bin/omarchy-menu"

# Delegate system updates to ujust update (handles bootc + flatpak + brew).
cat > "${SKEL_OMARCHY}/bin/omarchy-update" <<'EOF'
#!/usr/bin/env bash
exec ujust update "$@"
EOF
chmod +x "${SKEL_OMARCHY}/bin/omarchy-update"

# Waybar's custom/update module calls this every 6h. Upstream version does
# `git ls-remote` against $OMARCHY_PATH expecting it to be a git clone —
# we cp -a without .git/ so that path errors. Rewrite to check rpm-ostree
# (staged bootc deployment) and Flatpak (pending app updates), which are
# the two things `ujust update` actually acts on.
cat > "${SKEL_OMARCHY}/bin/omarchy-update-available" <<'EOF'
#!/usr/bin/env bash
# Exit 0 + echo the message → waybar shows the module.
# Exit non-zero → waybar hides it.

if rpm-ostree status --json 2>/dev/null \
    | jq -e '.deployments[] | select(.staged == true)' >/dev/null 2>&1; then
    echo "System update staged — reboot to apply"
    exit 0
fi

if flatpak remote-ls --updates 2>/dev/null | grep -q .; then
    echo "Flatpak updates available"
    exit 0
fi

exit 1
EOF
chmod +x "${SKEL_OMARCHY}/bin/omarchy-update-available"

# Strip bindings whose targets don't exist on this image:
#   - omarchy-brightness-display-apple: Apple-hardware-specific helper
#   - voxtype: voice dictation, AUR-only with no Fedora port
require_upstream_literal \
    "${SKEL_OMARCHY}/default/hypr/bindings/utilities.conf" \
    'omarchy-brightness-display-apple' \
    'Apple brightness binding'
require_upstream_literal \
    "${SKEL_OMARCHY}/default/hypr/bindings/utilities.conf" \
    'voxtype record toggle' \
    'voxtype binding'
sed -i \
    -e '/omarchy-brightness-display-apple/d' \
    -e '/voxtype record toggle/d' \
    "${SKEL_OMARCHY}/default/hypr/bindings/utilities.conf"

# Delete hyprland window rules for apps we don't install. They're harmless
# (rules only fire on matching window classes), but removing keeps the
# default/ tree honest with what's actually on the image. If a future user
# installs any of these via Flatpak later, the rules live in the original
# omarchy repo — they can copy them back manually.
# We also strip the matching source= lines from apps.conf: Hyprland treats a
# source= pointing at a missing file as a config error and paints the red
# error bar at the top of the screen on every reload.
for app in 1password bitwarden davinci-resolve geforce localsend moonlight qemu retroarch steam telegram webcam-overlay; do
    rm -f "${SKEL_OMARCHY}/default/hypr/apps/${app}.conf"
    sed -i "\|apps/${app}\.conf\$|d" "${SKEL_OMARCHY}/default/hypr/apps.conf"
done

# Ship icon.txt + logo.txt (omarchy's ASCII branding) at the repo root;
# omarchy-font-set and friends reference $OMARCHY_PATH/icon.txt directly.
cp "${WORK}/omarchy/icon.txt" "${WORK}/omarchy/logo.txt" "${SKEL_OMARCHY}/"

# Branding overrides used by fastfetch + the screensaver (omarchy
# install/config/branding.sh). Users can edit ~/.config/omarchy/branding/
# to personalise the About page and screensaver ASCII without touching
# the upstream files.
mkdir -p /etc/skel/.config/omarchy/branding
cp "${WORK}/omarchy/icon.txt" /etc/skel/.config/omarchy/branding/about.txt
cp "${WORK}/omarchy/logo.txt" /etc/skel/.config/omarchy/branding/screensaver.txt

# Terminal: omarchy upstream picks Alacritty first in xdg-terminals.list.
# We ship ghostty (fully themed by omarchy alongside alacritty and kitty).
require_upstream_literal \
    /etc/skel/.config/xdg-terminals.list \
    'Alacritty.desktop' \
    'default xdg-terminal-exec terminal order'
sed -i 's/^Alacritty\.desktop$/com.mitchellh.ghostty.desktop/' \
    /etc/skel/.config/xdg-terminals.list

# Waybar's CPU module hardcodes `alacritty` on right-click (we don't ship it).
# Re-route through xdg-terminal-exec so it resolves to ghostty via our patched
# xdg-terminals.list — same UX as upstream without the alacritty dependency.
require_upstream_literal \
    /etc/skel/.config/waybar/config.jsonc \
    '"on-click-right": "alacritty"' \
    'waybar CPU right-click alacritty fallback'
sed -i 's|"on-click-right": "alacritty"|"on-click-right": "xdg-terminal-exec"|' \
    /etc/skel/.config/waybar/config.jsonc

# Re-target the bindings that have a direct Flatpak equivalent, and strip the
# ones whose backing apps are intentionally not layered into this image.
require_upstream_literal \
    /etc/skel/.config/hypr/bindings.conf \
    'bindd = SUPER SHIFT, G, Signal, exec, omarchy-launch-or-focus ^signal$ "uwsm-app -- signal-desktop"' \
    'Signal binding'
require_upstream_literal \
    /etc/skel/.config/hypr/bindings.conf \
    'bindd = SUPER SHIFT, O, Obsidian, exec, omarchy-launch-or-focus ^obsidian$ "uwsm-app -- obsidian -disable-gpu --enable-wayland-ime"' \
    'Obsidian binding'
sed -i \
    -e 's|bindd = SUPER SHIFT, G, Signal, exec, omarchy-launch-or-focus \^signal\$ "uwsm-app -- signal-desktop"|bindd = SUPER SHIFT, G, Signal, exec, omarchy-launch-or-focus signal "uwsm-app -- flatpak run org.signal.Signal"|' \
    -e 's|bindd = SUPER SHIFT, O, Obsidian, exec, omarchy-launch-or-focus \^obsidian\$ "uwsm-app -- obsidian -disable-gpu --enable-wayland-ime"|bindd = SUPER SHIFT, O, Obsidian, exec, omarchy-launch-or-focus obsidian "uwsm-app -- flatpak run md.obsidian.Obsidian --disable-gpu --enable-wayland-ime"|' \
    -e '/bindd = SUPER SHIFT, M, Music, exec, omarchy-launch-or-focus spotify/d' \
    -e '/bindd = SUPER SHIFT, D, Docker, exec, omarchy-launch-tui lazydocker/d' \
    -e '/bindd = SUPER SHIFT, W, Typora, exec, uwsm-app -- typora --enable-wayland-ime/d' \
    -e '/bindd = SUPER SHIFT, SLASH, Passwords, exec, uwsm-app -- 1password/d' \
    /etc/skel/.config/hypr/bindings.conf

# Browser: upstream omarchy-launch-browser resolves the .desktop via
# xdg-settings, which doesn't search Flatpak export paths. Replace it with
# a direct Zen Browser (Flatpak) wrapper — Zen is preinstalled via
# /usr/share/flatpak/preinstall.d/zen-browser.preinstall.
cat > "${SKEL_OMARCHY}/bin/omarchy-launch-browser" <<'EOF'
#!/usr/bin/env bash
# Translate omarchy's generic --private flag to Zen's --private-window.
args=("${@/--private/--private-window}")
exec setsid uwsm-app -- flatpak run app.zen_browser.zen "${args[@]}"
EOF
chmod +x "${SKEL_OMARCHY}/bin/omarchy-launch-browser"

# Hook omarchy's shell defaults into the user's login shell. Fedora's stock
# ~/.bashrc auto-sources everything under ~/.bashrc.d/ — drop a snippet there
# rather than editing the distro-maintained .bashrc itself.
mkdir -p /etc/skel/.bashrc.d
cat > /etc/skel/.bashrc.d/omarchy.sh <<'EOF'
# Starship prompt, aliases, env vars, history settings from omarchy.
[[ -f "$HOME/.local/share/omarchy/default/bashrc" ]] && \
    source "$HOME/.local/share/omarchy/default/bashrc"
EOF

# XCompose: standard location for user compose sequences (emoji, arrows, …).
# Relative symlink resolves the same way in /etc/skel and in any $HOME.
ln -s .local/share/omarchy/default/xcompose /etc/skel/.XCompose

# ── Walker + elephant service setup ─────────────────────────────────
# Walker v2 runs as a persistent service; keybindings invoke `walker --gui`
# which IPCs into the already-running instance. Upstream install/config/
# walker-elephant.sh drops an XDG autostart entry, a systemd user drop-in
# for restart-on-crash, and symlinks elephant's menu provider Lua files
# into ~/.config/elephant/. We replay that into skel so first-login
# sessions get walker auto-started and the "Style → Theme" / "Background"
# menus are populated.
mkdir -p /etc/skel/.config/autostart
cp "${SKEL_OMARCHY}/default/walker/walker.desktop" \
    /etc/skel/.config/autostart/walker.desktop

mkdir -p /etc/skel/.config/systemd/user/app-walker@autostart.service.d
cp "${SKEL_OMARCHY}/default/walker/restart.conf" \
    /etc/skel/.config/systemd/user/app-walker@autostart.service.d/restart.conf

mkdir -p /etc/skel/.config/elephant/menus
# Relative symlinks so they resolve the same in /etc/skel and any $HOME.
ln -s ../../../.local/share/omarchy/default/elephant/omarchy_themes.lua \
    /etc/skel/.config/elephant/menus/omarchy_themes.lua
ln -s ../../../.local/share/omarchy/default/elephant/omarchy_background_selector.lua \
    /etc/skel/.config/elephant/menus/omarchy_background_selector.lua

# ── nautilus-python extensions ──────────────────────────────────────
# Upstream install/config/nautilus-python.sh copies localsend.py into the
# user's extensions dir. Relative symlink so it picks up updates on each
# OMARCHY_REF bump and resolves the same in skel and any $HOME.
mkdir -p /etc/skel/.local/share/nautilus-python/extensions
ln -sf ../../omarchy/default/nautilus-python/extensions/localsend.py \
    /etc/skel/.local/share/nautilus-python/extensions/localsend.py

# ── Claude Code skill symlink ───────────────────────────────────────
# Upstream install/config/omarchy-ai-skill.sh exposes the shipped omarchy
# skill under ~/.claude/skills/ for Claude Code. Relative symlink so it
# resolves the same in skel and any $HOME.
mkdir -p /etc/skel/.claude/skills
ln -sf ../../.local/share/omarchy/default/omarchy-skill \
    /etc/skel/.claude/skills/omarchy

# ── Bootstrap the initial theme ─────────────────────────────────────
# Replays bin/omarchy-theme-set's logic against /etc/skel so first login
# finds ~/.config/omarchy/current/theme/ fully populated with rendered
# per-app files (alacritty.toml, kitty.conf, ghostty.conf, waybar.css,
# mako.ini, hyprland.conf theme, hyprlock.conf, swayosd.css, walker.css,
# btop.theme, keyboard.rgb, …) generated from colors.toml + default/themed/
# templates. After this, `omarchy-theme-set <any-theme>` swaps atomically
# and restart-* / theme-set-* scripts fire just as on upstream omarchy.
(
    # Subshell-scoped so the exports don't leak into later build steps.
    export HOME=/etc/skel
    export OMARCHY_PATH="${SKEL_OMARCHY}"

    NEXT="${HOME}/.config/omarchy/current/next-theme"
    CURRENT="${HOME}/.config/omarchy/current/theme"
    INITIAL_THEME=tokyo-night

    [[ -d "${OMARCHY_PATH}/themes/${INITIAL_THEME}" ]] || {
        echo "Pinned Omarchy ref ${OMARCHY_REF} is missing theme ${INITIAL_THEME}" >&2
        exit 1
    }

    mkdir -p "${NEXT}"
    cp -a "${OMARCHY_PATH}/themes/${INITIAL_THEME}/." "${NEXT}/"

    # Runs `sed` against every *.tpl under default/themed/, substituting
    # `{{ <key> }}` placeholders with values from next-theme/colors.toml.
    bash "${OMARCHY_PATH}/bin/omarchy-theme-set-templates"

    rm -rf "${CURRENT}"
    mv "${NEXT}" "${CURRENT}"
    echo "${INITIAL_THEME}" > "${HOME}/.config/omarchy/current/theme.name"

    # App-specific symlinks into the current theme. Upstream omarchy sets
    # these up in install/config/theme.sh; replay them here so btop and mako
    # pick up themed colors/style on first boot without waiting for the
    # first `omarchy-theme-set` invocation.
    mkdir -p "${HOME}/.config/btop/themes"
    ln -sf ../../omarchy/current/theme/btop.theme \
        "${HOME}/.config/btop/themes/current.theme"

    mkdir -p "${HOME}/.config/mako"
    ln -sf ../omarchy/current/theme/mako.ini \
        "${HOME}/.config/mako/config"

    # Seed ~/.config/omarchy/current/background with the first theme
    # background. omarchy-theme-bg-next handles cycling at runtime, but
    # without a symlink in place hyprlock + swaybg have nothing to render
    # on first login. Relative path (from current/ down into theme/) so
    # it resolves identically in /etc/skel and any $HOME.
    first_bg=$(find "${CURRENT}/backgrounds" -maxdepth 1 -type f \
        \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \) \
        | sort | head -n1)
    if [[ -n $first_bg ]]; then
        ln -sf \
            "theme/backgrounds/$(basename "$first_bg")" \
            "${HOME}/.config/omarchy/current/background"
    fi
)

# ── SDDM ─────────────────────────────────────────────────────────────
# Omarchy ships its own Qt Quick SDDM theme. Deploy it system-wide;
# /etc/sddm.conf.d/theme.conf points at this theme name.
cp -a "${WORK}/omarchy/default/sddm/omarchy" /usr/share/sddm/themes/omarchy

# ── Font default: CaskaydiaMono Nerd Font ───────────────────────────
# Omarchy's upstream default is JetBrainsMono Nerd Font; switch every
# reference in the deployed configs to CaskaydiaMono (shipped by the
# che/nerd-fonts COPR as part of the nerd-fonts meta-package).
find /etc/skel /usr/share/sddm/themes/omarchy -type f -exec \
    sed -i 's/JetBrainsMono Nerd Font/CaskaydiaMono Nerd Font/g' {} +

rm -rf "${WORK}"
