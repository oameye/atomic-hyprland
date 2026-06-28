#!/usr/bin/env bash
# Shared build inputs. Keep pinned refs here so layer-1 source builds,
# layer-2 metadata, local builds, and CI all pull from one place.
#
# shellcheck disable=SC2034
# Reason: this file is a sourced data module; the variables are consumed by
# other scripts, not within this file itself.

FEDORA_VERSION="44"
OMARCHY_REF="v3.8.2"

# The entire hyprwm ecosystem (compositor, libs, satellites, Qt6 components) is
# installed from this COPR (see packages.sh) instead of being source-built. The
# COPR only ships Hyprland as a rolling git build (hyprland-git); there is no
# stable hyprland RPM for Fedora, so there is no upstream tag to pin here. The
# COPR is rebuilt every other Saturday and we take whatever it publishes.
HYPRLAND_COPR="craftidore/wayblueorg-hyprland"

SATTY_TAG="v0.21.1"
HYPRSHOT_TAG="1.3.0"
CLIPHIST_TAG="v0.7.0"
UWSM_TAG="v0.26.4"
XDG_TERMINAL_EXEC_TAG="v0.14.2"
WALKER_TAG="v2.16.2"
ELEPHANT_TAG="v2.21.0"
WIREMIX_TAG="v0.10.0"
BLUETUI_TAG="v0.8.1"
IMPALA_TAG="v0.7.4"
GUM_TAG="v0.17.0"
STARSHIP_TAG="v1.25.1"
HYPRLAND_PREVIEW_SHARE_PICKER_TAG="v0.2.1"
NERD_FONTS_TAG="v3.4.0"

# Emit these into /usr/share/atomic-hyprland/versions.env for build provenance.
VERSION_METADATA_VARS=(
	FEDORA_VERSION
	OMARCHY_REF
	HYPRLAND_COPR
	SATTY_TAG
	HYPRSHOT_TAG
	CLIPHIST_TAG
	UWSM_TAG
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
