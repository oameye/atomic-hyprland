export image_name := env("IMAGE_NAME", "atomic-hyprland")
export default_tag := env("DEFAULT_TAG", "43")

[private]
default:
    @just --list

# Verify Justfile syntax.
[group('Just')]
check:
    #!/usr/bin/env bash
    set -eou pipefail
    echo "Checking syntax: Justfile"
    just --unstable --fmt --check -f Justfile

# Fix Justfile syntax in place.
[group('Just')]
fix:
    #!/usr/bin/env bash
    set -eou pipefail
    just --unstable --fmt -f Justfile

# Remove local build artefacts.
[group('Utility')]
clean:
    #!/usr/bin/env bash
    set -eou pipefail
    rm -rf output _build *_build*
    rm -f previous.manifest.json changelog.md output.env

# Build the image with podman. Usage: just build [target_image] [tag]
[group('Build')]
build $target_image=image_name $tag=default_tag:
    #!/usr/bin/env bash
    set -eou pipefail
    source build_files/pins.sh

    BUILD_ARGS=()
    if [[ -z "$(git status -s)" ]]; then
        BUILD_ARGS+=("--build-arg" "SHA_HEAD_SHORT=$(git rev-parse --short HEAD)")
    fi

    podman build \
        "${BUILD_ARGS[@]}" \
        --pull=newer \
        --build-arg "FEDORA_VERSION=${FEDORA_VERSION}" \
        --tag "${target_image}:${tag}" \
        .

# Run shellcheck on all .sh scripts.
[group('Check')]
lint:
    #!/usr/bin/env bash
    set -eou pipefail
    if ! command -v shellcheck &> /dev/null; then
        echo "shellcheck not found. Install it (e.g. brew install shellcheck)."
        exit 1
    fi
    /usr/bin/find . -iname "*.sh" -type f -exec shellcheck "{}" ';'

# Re-run build_files/verify.sh inside an already-built image. Usage: just verify [tag]
[group('Check')]
verify $tag=default_tag:
    #!/usr/bin/env bash
    set -eou pipefail
    podman run --rm \
        -v ./build_files:/build_files:ro,Z \
        "${image_name}:${tag}" \
        bash /build_files/verify.sh

# Run shfmt on all .sh scripts.
[group('Check')]
format:
    #!/usr/bin/env bash
    set -eou pipefail
    if ! command -v shfmt &> /dev/null; then
        echo "shfmt not found. Install it (e.g. brew install shfmt)."
        exit 1
    fi
    /usr/bin/find . -iname "*.sh" -type f -exec shfmt --write "{}" ';'
