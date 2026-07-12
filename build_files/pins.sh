#!/usr/bin/env bash
# Shared build inputs. Keep pinned refs here so layer-1 source builds,
# layer-2 metadata, local builds, and CI all pull from one place.
#
# shellcheck disable=SC2034
# Reason: this file is a sourced data module; the variables are consumed by
# other scripts, not within this file itself.

FEDORA_VERSION="44"
OMARCHY_REF="v3.5.1"

# The entire hyprwm ecosystem (compositor, libs, satellites, Qt6 components) is
# installed from this COPR (see packages.sh) instead of being source-built. The
# COPR only ships Hyprland as a rolling git build (hyprland-git) that tracks
# upstream master and is rebuilt every other Saturday. Tracking that tip blindly
# is a liability: a bad master snapshot (0.55.4^43.git14fa1fd) once shipped a
# compositor that SIGABRTed on the first surface map, crash-looping the session.
# So the compositor is pinned to a specific known-good build below rather than
# taking whatever the COPR last published. The COPR retains old builds, so the
# pin stays installable. Renovate proposes bumps via a custom COPR datasource
# (see .github/renovate.json5); every bump MUST be boot-tested before merge.
HYPRLAND_COPR="craftidore/wayblueorg-hyprland"
# Exact hyprland-git build to install (NEVRA version only; dnf appends -N.fcNN).
HYPRLAND_GIT_VERSION="0.55.4^3.git9556660"

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
	HYPRLAND_GIT_VERSION
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
