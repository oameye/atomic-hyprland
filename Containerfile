# Global build arg -- must be declared before the first FROM to be
# usable in a downstream FROM. Re-declare in stages that reference it.
ARG FEDORA_VERSION=43

FROM scratch AS source_ctx
COPY build_files/source-build*.sh /
COPY build_files/pins.sh /
COPY build_files/repos.sh /

FROM scratch AS build_ctx
COPY build_files /

FROM ghcr.io/ublue-os/base-main:${FEDORA_VERSION}

# Source build layers are intentionally split for remote layer-cache reuse.
# hadolint ignore=DL3059
RUN --mount=type=bind,from=source_ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    bash /ctx/source-build-setup.sh

# hadolint ignore=DL3059
RUN --mount=type=bind,from=source_ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    bash /ctx/source-build-core.sh

# hadolint ignore=DL3059
RUN --mount=type=bind,from=source_ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    bash /ctx/source-build-hyprland.sh

# hadolint ignore=DL3059
RUN --mount=type=bind,from=source_ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    bash /ctx/source-build-tools.sh

# hadolint ignore=DL3059
RUN --mount=type=bind,from=source_ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    bash /ctx/source-build-cleanup.sh

# System overlay + brew + bling
COPY files/ /
COPY --from=ghcr.io/ublue-os/brew:latest /system_files /
COPY --from=ghcr.io/ublue-os/bluefin:stable \
    /usr/share/ublue-os/bling /usr/share/ublue-os/bling

# Layer 2 - system config
RUN --mount=type=bind,from=build_ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    bash /ctx/build.sh \
 && /usr/bin/systemctl preset brew-setup.service \
 && /usr/bin/systemctl preset brew-update.timer \
 && /usr/bin/systemctl preset brew-upgrade.timer \
 && ostree container commit

RUN bootc container lint
