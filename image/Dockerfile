# syntax=docker/dockerfile:1
FROM debian:bookworm-slim AS build
ARG SBCL_VERSION=2.6.7
ARG TARGETARCH
ENV SBCL_VERSION=${SBCL_VERSION} TARGETARCH=${TARGETARCH}
COPY image/init.c image/boot.lisp image/assemble-rootfs.sh image/nsswitch.conf image/hosts /src/image/
COPY image/pack-inside.lisp /opt/cl-microvm/pack-inside.lisp
RUN sh /src/image/assemble-rootfs.sh

FROM scratch AS runtime
COPY --from=build /rootfs/ /
ENV SBCL_HOME=/usr/local/lib/sbcl \
    HOME=/data \
    XDG_CACHE_HOME=/opt/cache \
    PATH=/usr/local/bin:/usr/bin:/bin
ENTRYPOINT ["/init"]

FROM build AS builder
RUN apt-get update \
    && apt-get install -y --no-install-recommends e2fsprogs ca-certificates \
    && rm -rf /var/lib/apt/lists/*
ENV SBCL_HOME=/usr/local/lib/sbcl \
    HOME=/tmp/home \
    XDG_CACHE_HOME=/opt/cache \
    PATH=/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
WORKDIR /opt/cl-microvm
ENTRYPOINT ["/usr/local/bin/sbcl", "--disable-debugger", "--non-interactive", "--load", "/opt/cl-microvm/pack-inside.lisp"]
