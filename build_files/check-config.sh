#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${DIR}/.." && pwd)"
cd "${REPO_ROOT}"

source "${DIR}/pins.sh"

fail_count=0

fail() {
    echo "FAIL: $*" >&2
    fail_count=$((fail_count + 1))
}

expect_equal() {
    local actual="$1" expected="$2" description="$3"
    if [[ $actual != "$expected" ]]; then
        fail "${description}: expected '${expected}', got '${actual}'"
    fi
}

container_fedora_version="$(sed -n 's/^ARG FEDORA_VERSION=//p' Containerfile)"
expect_equal "${container_fedora_version}" "${FEDORA_VERSION}" \
    "Containerfile FEDORA_VERSION fallback"

if ! grep -Fxq \
    'export default_tag := env("DEFAULT_TAG", `bash -lc '\''source build_files/pins.sh && printf %s "$FEDORA_VERSION"'\''`)' \
    Justfile; then
    fail "Justfile default_tag is not sourced from build_files/pins.sh"
fi

mapfile -t stray_pins < <(
    rg -n '^[A-Z0-9_]+_(TAG|REF)=' build_files --glob '!pins.sh'
)
if (( ${#stray_pins[@]} > 0 )); then
    fail "$(printf 'found pinned refs outside build_files/pins.sh:\n%s\n' "${stray_pins[@]}")"
fi

mapfile -t stray_manifests < <(
    rg -n '^(SOURCE_BUILT_HYPRWM_EXECUTABLES|SOURCE_BUILT_AUX_EXECUTABLES|PACKAGED_DESKTOP_EXECUTABLES|SYSTEM_UNITS|GLOBAL_UNITS)=' \
        build_files --glob '!manifest.sh'
)
if (( ${#stray_manifests[@]} > 0 )); then
    fail "$(printf 'found manifest arrays outside build_files/manifest.sh:\n%s\n' "${stray_manifests[@]}")"
fi

if (( fail_count > 0 )); then
    exit 1
fi

echo "build config checks passed"
