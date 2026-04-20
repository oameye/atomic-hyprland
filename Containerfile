# Global build arg -- must be declared before the first FROM to be
# usable in a downstream FROM. Re-declare in stages that reference it.
ARG FEDORA_VERSION=43

# Keep build scripts out of the final image by referencing them via a bind
# mount from a scratch context stage (pattern from ublue-os/image-template).
FROM scratch AS ctx
COPY build_files /

# Base image
FROM ghcr.io/ublue-os/base-main:${FEDORA_VERSION}

# Layer 1 — repos + source builds.
# Keep this ahead of filesystem overlays and floating upstream COPY sources so
# unrelated changes do not invalidate the expensive compile layer.
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/source-builds.sh

# System-file overlay (systemd units, dx-groups helper, SDDM confs, etc.)
COPY files/ /

# Homebrew: base-main does NOT ship brew. Pull the tarball + systemd units
# from ublue-os/brew (the canonical pattern, used by Bluefin/Aurora). The
# brew-setup oneshot extracts the tarball into /var/home/linuxbrew on first
# boot; /etc/profile.d/brew.sh adds brew to PATH for interactive shells.
COPY --from=ghcr.io/ublue-os/brew:latest /system_files /

# Bling: opt-in shell init that auto-aliases brew-installed CLI tools
# (eza->ls/ll, bat->cat, ug->grep, starship/zoxide/mise/direnv hooks).
# User sources /usr/share/ublue-os/bling/bling.sh from ~/.bashrc / ~/.zshrc
# (or bling.fish for fish). Does nothing if the underlying tools are
# absent. Copied straight from the bluefin image since there is no
# separate OCI image or RPM for it.
COPY --from=ghcr.io/ublue-os/bluefin:stable \
    /usr/share/ublue-os/bling /usr/share/ublue-os/bling

# Layer 2 — packages, desktop, systemd, cleanup.
# Inherits repos from Layer 1; rebuilds on every package-list or rice change.
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build.sh \
 && /usr/bin/systemctl preset brew-setup.service \
 && /usr/bin/systemctl preset brew-update.timer \
 && /usr/bin/systemctl preset brew-upgrade.timer \
 && ostree container commit

# Validate the final image against bootc expectations.
RUN bootc container lint
