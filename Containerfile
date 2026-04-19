# Global build arg -- must be declared before the first FROM to be
# usable in a downstream FROM. Re-declare in stages that reference it.
ARG FEDORA_VERSION=43

# Keep build scripts out of the final image by referencing them via a bind
# mount from a scratch context stage (pattern from ublue-os/image-template).
FROM scratch AS ctx
COPY build_files /

# Base image
FROM ghcr.io/ublue-os/base-main:${FEDORA_VERSION}

# System-file overlay (systemd units, dx-groups helper, SDDM confs, etc.)
COPY files/ /

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build.sh \
 && ostree container commit

# Validate the final image against bootc expectations.
RUN bootc container lint
