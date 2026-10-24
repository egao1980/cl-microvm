#!/bin/bash
# Build the Firecracker guest vmlinux for this machine's Docker arch.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
arch="$(docker info --format '{{.Architecture}}')"
case "$arch" in
    aarch64|arm64) kern_arch=arm64 ;;
    x86_64|amd64) kern_arch=amd64 ;;
    *) echo "unsupported docker arch $arch" >&2; exit 1 ;;
esac
docker build -f "$ROOT/kernel/Dockerfile" --build-arg "ARCH=$kern_arch" -t cl-microvm:kernel "$ROOT/kernel"
mkdir -p "$ROOT/dist"
cid="$(docker create cl-microvm:kernel)"
docker cp "$cid:/src/vmlinux" "$ROOT/dist/vmlinux"
if [[ "$kern_arch" == arm64 ]]; then
    docker cp "$cid:/src/Image" "$ROOT/dist/Image"
fi
docker rm "$cid" >/dev/null
echo "kernel $ROOT/dist/vmlinux"
