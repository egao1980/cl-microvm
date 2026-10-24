# syntax=docker/dockerfile:1
# Firecracker guest kernel. QEMU's microvm machine is x86_64; aarch64 boots with -M virt.
FROM debian:bookworm-slim
ARG ARCH=arm64
ARG LINUX_VERSION=6.1.112
ARG FIRECRACKER_TAG=v1.12.1
RUN apt-get update && apt-get install -y --no-install-recommends \
        bc bison build-essential ca-certificates curl flex libelf-dev libssl-dev xz-utils \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /src
RUN curl -fsSL -o linux.tar.xz \
        "https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-${LINUX_VERSION}.tar.xz" \
    && tar -xf linux.tar.xz \
    && rm linux.tar.xz
COPY fragment.config /src/fragment.config
RUN set -eu; \
    case "$ARCH" in \
        arm64) cfg=microvm-kernel-ci-aarch64-6.1.config; karch=arm64 ;; \
        amd64) cfg=microvm-kernel-ci-x86_64-6.1.config; karch=x86_64 ;; \
        *) echo "unsupported ARCH=$ARCH"; exit 1 ;; \
    esac; \
    curl -fsSL -o /src/linux-${LINUX_VERSION}/.config \
        "https://raw.githubusercontent.com/firecracker-microvm/firecracker/${FIRECRACKER_TAG}/resources/guest_configs/${cfg}"; \
    cd /src/linux-${LINUX_VERSION}; \
    ./scripts/kconfig/merge_config.sh -m .config /src/fragment.config; \
    make olddefconfig ARCH="$karch"; \
    if [ "$karch" = arm64 ]; then targets="vmlinux Image"; else targets="vmlinux bzImage"; fi; \
    make -j"$(nproc)" $targets ARCH="$karch"; \
    if [ "$karch" = arm64 ]; then cp arch/arm64/boot/Image /src/Image; fi; \
    if [ "$karch" = x86_64 ]; then cp arch/x86/boot/bzImage /src/bzImage; fi; \
    cp vmlinux /src/vmlinux; \
    cd /src; \
    rm -rf "linux-${LINUX_VERSION}"
