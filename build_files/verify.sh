#!/usr/bin/env bash
# Post-build smoke assertions. Runs at the end of build.sh (inside the
# image's final rootfs). Each failing assertion prints to stderr and
# increments fail_count; exit 1 at the end if any failed.
#
# Scope: catch regressions that are invisible to `bootc container lint`
# — missing source-built binaries, unstripped omarchy install scripts,
# broken sed patches, theme bootstrap not producing a real directory,
# systemd units not enabled. Runtime behaviour (e.g. does Hyprland
# actually start a compositor) is out of scope; that needs a VM boot.
set -uo pipefail

DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${DIR}/pins.sh"
source "${DIR}/manifest.sh"

fail_count=0

fail() {
	echo "  FAIL: $*" >&2
	fail_count=$((fail_count + 1))
}

want_exec() {
	local path="$1"
	if [[ ! -x $path ]]; then
		fail "$path missing or not executable"
	fi
}

want_file() {
	local path="$1"
	if [[ ! -f $path ]]; then
		fail "$path missing"
	fi
}

want_line() {
	local line="$1" file="$2"
	if [[ ! -f $file ]]; then
		fail "$file missing (wanted line '$line')"
		return
	fi
	if ! grep -Fxq "$line" "$file"; then
		fail "$file missing exact line '$line'"
	fi
}

want_dir_real() {
	local path="$1"
	if [[ -L $path ]]; then
		fail "$path is a symlink (expected real directory)"
	elif [[ ! -d $path ]]; then
		fail "$path missing or not a directory"
	fi
}

want_absent() {
	local pattern="$1"
	local matches
	matches=$(compgen -G "$pattern" || true)
	if [[ -n $matches ]]; then
		fail "expected no matches for '$pattern', found: $matches"
	fi
}

want_grep() {
	local pattern="$1" file="$2"
	if [[ ! -f $file ]]; then
		fail "$file missing (wanted to grep '$pattern')"
		return
	fi
	if ! grep -qE "$pattern" "$file"; then
		fail "$file does not match /$pattern/"
	fi
}

want_nogrep() {
	local pattern="$1" file="$2"
	if [[ -f $file ]] && grep -qE "$pattern" "$file"; then
		fail "$file still matches /$pattern/"
	fi
}

want_unit_enabled() {
	local scope="$1" unit="$2"
	if [[ $scope == global ]]; then
		if ! systemctl --global is-enabled --quiet "$unit"; then
			fail "global systemd unit $unit is not enabled"
		fi
		return
	fi
	if ! systemctl is-enabled --quiet "$unit"; then
		fail "systemd unit $unit is not enabled"
	fi
}

echo "==> Source-built hyprwm binaries"
for path in "${SOURCE_BUILT_HYPRWM_EXECUTABLES[@]}"; do
	want_exec "$path"
done

echo "==> Source-built non-hyprwm binaries"
for path in "${SOURCE_BUILT_AUX_EXECUTABLES[@]}"; do
	want_exec "$path"
done

echo "==> Elephant provider plugins"
if ! compgen -G '/etc/xdg/elephant/providers/*.so' >/dev/null; then
	fail "/etc/xdg/elephant/providers/ has no .so plugins"
fi

echo "==> Walker system config"
want_file /etc/xdg/walker/config.toml
want_dir_real /etc/xdg/walker/themes/default

echo "==> JetBrainsMono Nerd Font"
if ! compgen -G '/usr/share/fonts/jetbrains-mono-nerd/*.ttf' >/dev/null; then
	fail "/usr/share/fonts/jetbrains-mono-nerd/ has no .ttf files"
fi
want_file /etc/fonts/conf.d/80-atomic-hyprland-monospace.conf

echo "==> Packaged desktop apps"
for path in "${PACKAGED_DESKTOP_EXECUTABLES[@]}"; do
	want_exec "$path"
done

echo "==> Firefox removed"
want_absent '/usr/bin/firefox'

echo "==> Omarchy skel layout"
SKEL=/etc/skel/.local/share/omarchy
want_dir_real "$SKEL/default"
want_dir_real "$SKEL/themes"
want_dir_real "$SKEL/bin"
want_file "$SKEL/icon.txt"
want_file "$SKEL/logo.txt"

echo "==> Stripped omarchy install/pkg scripts"
for glob in "$SKEL/bin/omarchy-install-*" "$SKEL/bin/omarchy-pkg-*" \
	"$SKEL/bin/omarchy-webapp-*" "$SKEL/bin/omarchy-tui-*" \
	"$SKEL/bin/omarchy-windows-*" \
	"$SKEL/bin/omarchy-refresh-pacman" \
	"$SKEL/bin/omarchy-channel-set" \
	"$SKEL/bin/omarchy-update-system-pkgs" \
	"$SKEL/bin/omarchy-update-aur-pkgs" \
	"$SKEL/bin/omarchy-update-keyring" \
	"$SKEL/bin/omarchy-version-channel"; do
	want_absent "$glob"
done

echo "==> Omarchy-menu Install entry sed-stripped"
want_nogrep '󰉉  Install' "$SKEL/bin/omarchy-menu"
want_nogrep '\*install\*\)' "$SKEL/bin/omarchy-menu"
want_nogrep '󰔫  Channel' "$SKEL/bin/omarchy-menu"

echo "==> omarchy-update stub delegates to ujust update"
want_grep 'exec ujust update' "$SKEL/bin/omarchy-update"

echo "==> Theme bootstrap produced a real directory"
want_dir_real /etc/skel/.config/omarchy/current/theme
want_file /etc/skel/.config/omarchy/current/theme.name
want_grep '^tokyo-night$' /etc/skel/.config/omarchy/current/theme.name
# current/background is a relative symlink into theme/backgrounds/; resolve it.
if [[ ! -L /etc/skel/.config/omarchy/current/background ]]; then
	fail "/etc/skel/.config/omarchy/current/background is not a symlink"
elif [[ ! -e /etc/skel/.config/omarchy/current/background ]]; then
	fail "/etc/skel/.config/omarchy/current/background symlink is broken"
fi

echo "==> Ghostty is the xdg-terminal-exec default"
want_grep '^com\.mitchellh\.ghostty\.desktop$' /etc/skel/.config/xdg-terminals.list
want_nogrep '^Alacritty\.desktop$' /etc/skel/.config/xdg-terminals.list

echo "==> Waybar CPU binding re-routed off alacritty"
want_grep '"on-click-right": "xdg-terminal-exec"' /etc/skel/.config/waybar/config.jsonc
want_nogrep '"on-click-right": "alacritty"' /etc/skel/.config/waybar/config.jsonc

echo "==> PAM / faillock tweaks applied"
want_grep '^deny = 10' /etc/security/faillock.conf
# authselect with-faillock must have injected pam_faillock into the auth
# chain; without this, faillock.conf is configured but never consulted.
want_grep 'pam_faillock\.so preauth' /etc/pam.d/system-auth
want_grep 'pam_faillock\.so authfail' /etc/pam.d/system-auth
want_grep 'pam_faillock\.so preauth' /etc/pam.d/password-auth
want_grep 'pam_faillock\.so authfail' /etc/pam.d/password-auth
want_nogrep 'pam_faillock\.so preauth' /etc/pam.d/sddm-autologin
want_grep 'pam_faillock\.so authsucc' /etc/pam.d/sddm-autologin

echo "==> nsswitch mDNS shim applied"
want_grep 'mdns_minimal \[NOTFOUND=return\]' /etc/nsswitch.conf

echo "==> Power button handler"
want_grep '^HandlePowerKey=ignore' /usr/lib/systemd/logind.conf.d/atomic-hyprland-power.conf

echo "==> Chromium managed policy baseline"
want_file /etc/chromium/policies/managed/color.json
want_grep 'BrowserThemeColor' /etc/chromium/policies/managed/color.json

echo "==> Plymouth omarchy theme installed"
want_dir_real /usr/share/plymouth/themes/omarchy

echo "==> Version metadata"
want_file /usr/share/atomic-hyprland/versions.env
for var_name in "${VERSION_METADATA_VARS[@]}"; do
	want_line "${var_name}=${!var_name}" /usr/share/atomic-hyprland/versions.env
done
want_grep '^OMARCHY_COMMIT=[0-9a-f]{40}$' /usr/share/atomic-hyprland/versions.env

echo "==> Systemd units enabled"
for unit in "${SYSTEM_UNITS[@]}"; do
	want_unit_enabled system "$unit"
done

echo "==> Global systemd units enabled"
for unit in "${GLOBAL_UNITS[@]}"; do
	want_unit_enabled global "$unit"
done

echo
if ((fail_count > 0)); then
	echo "verify.sh: $fail_count assertion(s) failed" >&2
	exit 1
fi
echo "verify.sh: all assertions passed"
