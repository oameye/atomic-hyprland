#!/usr/bin/env bash
set -euo pipefail

WORK=$(mktemp -d)

# ── SDDM ────────────────────────────────────────────────────────────
git clone --depth 1 --branch "${SDDM_HYPRLAND_TAG}" \
    https://github.com/HyDE-Project/sddm-hyprland.git "${WORK}/sddm-hyprland"
make -C "${WORK}/sddm-hyprland" install PREFIX=/usr

git clone https://github.com/keyitdev/sddm-astronaut-theme.git \
    /usr/share/sddm/themes/sddm-astronaut-theme
git -C /usr/share/sddm/themes/sddm-astronaut-theme reset --hard "${SDDM_ASTRONAUT_COMMIT}"
rm -rf /usr/share/sddm/themes/sddm-astronaut-theme/.git
cp -r /usr/share/sddm/themes/sddm-astronaut-theme/Fonts/* /usr/share/fonts/
sed -i "s|^ConfigFile=.*|ConfigFile=Themes/${SDDM_ASTRONAUT_VARIANT}.conf|" \
    /usr/share/sddm/themes/sddm-astronaut-theme/metadata.desktop

# ── Hyprland-Dots ────────────────────────────────────────────────────
git clone --depth 1 https://github.com/LinuxBeginnings/Hyprland-Dots.git \
    "${WORK}/hyprland-dots"

mkdir -p /etc/skel/.config
cp -a "${WORK}/hyprland-dots/config/." /etc/skel/.config/

# Override upstream defaults: ghostty as terminal, nautilus as file manager.
# shellcheck disable=SC2016  # $term/$files are Hyprland config syntax, not shell vars.
sed -i \
    -e 's|^\$term\s*=.*|$term = ghostty|' \
    -e 's|^\$files\s*=.*|$files = nautilus|' \
    /etc/skel/.config/hypr/UserConfigs/01-UserDefaults.conf

rm -rf "${WORK}"
