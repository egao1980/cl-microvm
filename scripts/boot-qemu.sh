#!/bin/bash
# Boot dist/root or an ext4 under QEMU.
# aarch64: -M virt, console=ttyAMA0 (QEMU microvm is x86_64-only).
# amd64:   -M microvm, console=ttyS0.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DISK="${1:-$ROOT/dist/hello.ext4}"
if [[ "$DISK" != /* ]]; then
    DISK="$ROOT/$DISK"
fi
ARCH="${2:-arm64}"
case "$ARCH" in
    arm64)
        machine=virt
        console=ttyAMA0
        qemu=qemu-system-aarch64
        kernel="$ROOT/dist/Image"
        extra=(-cpu max -machine virt,gic-version=3)
        ;;
    amd64)
        machine=microvm
        console=ttyS0
        qemu=qemu-system-x86_64
        kernel="$ROOT/dist/vmlinux"
        extra=(-M microvm)
        ;;
    *) echo "arch is arm64 or amd64" >&2; exit 1 ;;
esac
[[ -f "$DISK" && -f "$kernel" ]] || { echo "missing $DISK or $kernel" >&2; exit 1; }
append="console=${console} reboot=k panic=1 pci=off nomodules root=/dev/vda rw rootfstype=ext4 rootwait init=/init ip=dhcp"
docker run --rm -v "$ROOT/dist:/dist" -v "$DISK:/disk.ext4" debian:bookworm-slim \
    bash -c "apt-get update -qq && apt-get install -y -qq qemu-system-arm qemu-system-x86 >/dev/null && \
      timeout 180 ${qemu} ${extra[*]} -kernel /dist/$(basename "$kernel") \
        -append '${append}' \
        -drive file=/disk.ext4,if=none,format=raw,id=root,cache=none \
        -device virtio-blk-device,drive=root \
        -netdev user,id=net0 -device virtio-net-device,netdev=net0 \
        -serial stdio -display none -m 512 -no-reboot"
