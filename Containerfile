ARG FEDORA_VERSION=43
FROM ghcr.io/ublue-os/base-main:${FEDORA_VERSION}

COPY files/ /
COPY build.sh /tmp/build.sh

RUN chmod +x /tmp/build.sh \
 && /tmp/build.sh \
 && ostree container commit
