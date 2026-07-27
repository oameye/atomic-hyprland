#!/usr/bin/env bash
# Shared build inputs. Keep pinned refs here so layer-1 source builds,
# layer-2 metadata, local builds, and CI all pull from one place.
#
# shellcheck disable=SC2034
# Reason: this file is a sourced data module; the variables are consumed by
# other scripts, not within this file itself.

FEDORA_VERSION="44"
OMARCHY_REF="v3.8.4"

# The entire hyprwm ecosystem (compositor, libs, satellites, Qt6 components),
# plus uwsm and the uwsm session file, are installed from this COPR (see
# packages.sh) instead of being source-built. The wayblueorg COPR only ships a
# rolling hyprland-git tracking master (a liability: a bad master snapshot once
# SIGABRTed on the first surface map and crash-looped the session). lionheartp
# instead packages tagged *stable* Hyprland releases, so we pin a released
# version rather than chasing master snapshots. The COPR retains old builds, so
# the pin stays installable. Renovate proposes bumps via a custom COPR datasource
# (see .github/renovate.json5); every bump MUST be boot-tested before merge.
HYPRLAND_COPR="lionheartp/Hyprland"
# Exact stable hyprland release to install (NEVRA version only; dnf appends -N.fcNN).
HYPRLAND_VERSION="0.56.0"

SATTY_TAG="v0.21.1"
HYPRSHOT_TAG="1.3.0"
CLIPHIST_TAG="v0.7.0"
XDG_TERMINAL_EXEC_TAG="v0.14.2"
WALKER_TAG="v2.17.0"
ELEPHANT_TAG="v2.22.0"
WIREMIX_TAG="v0.11.0"
BLUETUI_TAG="v0.8.1"
IMPALA_TAG="v0.7.4"
GUM_TAG="v0.17.0"
STARSHIP_TAG="v1.26.0"
HYPRLAND_PREVIEW_SHARE_PICKER_TAG="v0.2.1"
NERD_FONTS_TAG="v3.4.0"

# Emit these into /usr/share/atomic-hyprland/versions.env for build provenance.
VERSION_METADATA_VARS=(
	FEDORA_VERSION
	OMARCHY_REF
	HYPRLAND_COPR
	HYPRLAND_VERSION
	SATTY_TAG
	HYPRSHOT_TAG
	CLIPHIST_TAG
	XDG_TERMINAL_EXEC_TAG
	WALKER_TAG
	ELEPHANT_TAG
	WIREMIX_TAG
	BLUETUI_TAG
	IMPALA_TAG
	GUM_TAG
	STARSHIP_TAG
	HYPRLAND_PREVIEW_SHARE_PICKER_TAG
	NERD_FONTS_TAG
)
