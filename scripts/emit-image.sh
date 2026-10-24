#!/bin/bash
# Emit a project image from a local .asd using cl-microvm:builder.
# Usage: emit-image.sh <system> <project-dir> [tag] [base-image]
set -euo pipefail

SYSTEM="${1:?system name}"
PROJECT="$(cd "${2:?project dir}" && pwd)"
TAG="${3:-}"
BASE="${4:-cl-microvm:sbcl-2.6.7}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

if ! docker image inspect "$BASE" >/dev/null 2>&1 || ! docker image inspect cl-microvm:builder >/dev/null 2>&1; then
    "$ROOT/scripts/build-image.sh"
fi

mkdir -p "$WORKDIR/context/app" "$WORKDIR/context/cl" "$WORKDIR/context/cache"

args=(
    docker run --rm --privileged --entrypoint /bin/bash
    -e "CL_SYSTEM=$SYSTEM"
    -e XDG_CACHE_HOME=/opt/cache
    -v "$PROJECT:/src:ro"
    -v "$WORKDIR/context:/out"
)
if [[ -n "${CL_REPOSITORY:-}" && -d "$CL_REPOSITORY" ]]; then
    args+=(-v "$CL_REPOSITORY:/opt/cl-repository:ro")
fi
if [[ -n "${QUICKLISP_SETUP:-}" && -f "$QUICKLISP_SETUP" ]]; then
    ql_dir="$(cd "$(dirname "$QUICKLISP_SETUP")" && pwd)"
    args+=(-v "$ql_dir:/quicklisp:ro" -e QUICKLISP_SETUP=/quicklisp/setup.lisp)
fi
args+=(cl-microvm:builder -c '
set -eu
rm -rf /opt/app
mkdir -p /opt/app /opt/cl /opt/cache /out/app /out/cl /out/cache /rootfs/opt/app /rootfs/opt/cl /rootfs/opt/cache
cp -a /src/. /opt/app/
/usr/local/bin/sbcl --disable-debugger --non-interactive --load /opt/cl-microvm/pack-inside.lisp
rm -rf /rootfs/opt/app /rootfs/opt/cl
mkdir -p /rootfs/opt/app /rootfs/opt/cl /rootfs/opt/cache
cp -a /opt/app/. /rootfs/opt/app/
if [ -n "$(ls -A /opt/cl 2>/dev/null || true)" ]; then
    cp -a /opt/cl/. /rootfs/opt/cl/
fi
if [ -n "$(ls -A /opt/cache 2>/dev/null || true)" ]; then
    cp -a /opt/cache/. /rootfs/opt/cache/
fi
chmod -R a+rX /rootfs/opt/app /rootfs/opt/cl /rootfs/opt/cache
chmod 1777 /rootfs/opt/cache
printf "CL_SYSTEM=%s\n" "$CL_SYSTEM" > /rootfs/etc/cl-microvm.env
cp /rootfs/etc/cl-microvm.env /out/cl-microvm.env
cp -a /opt/app/. /out/app/
if [ -n "$(ls -A /opt/cl 2>/dev/null || true)" ]; then
    cp -a /opt/cl/. /out/cl/
fi
if [ -n "$(ls -A /opt/cache 2>/dev/null || true)" ]; then
    cp -a /opt/cache/. /out/cache/
fi
chmod -R a+rX /out/app /out/cl /out/cache
chmod 1777 /out/cache
touch /out/cl/.keep /out/cache/.keep
mb=$(( $(du -sm /rootfs | cut -f1) + 256 ))
/usr/sbin/mkfs.ext4 -F -L cl-microvm /out/root.ext4 "${mb}M"
mkdir -p /mnt/root
mount -o loop /out/root.ext4 /mnt/root
cp -a /rootfs/. /mnt/root/
umount /mnt/root
')

"${args[@]}"

system_name="$(awk '$1=="system"{print $2}' "$WORKDIR/context/meta")"
version="$(awk '$1=="version"{print $2}' "$WORKDIR/context/meta")"
if [[ -z "$TAG" ]]; then
    TAG="cl-microvm-app:${system_name}-${version}"
fi

cat > "$WORKDIR/context/Dockerfile" <<EOF
FROM ${BASE}
COPY app/ /opt/app/
COPY cl/ /opt/cl/
COPY cache/ /opt/cache/
COPY cl-microvm.env /etc/cl-microvm.env
ENV CL_SYSTEM=${system_name}
EOF

docker build -t "$TAG" "$WORKDIR/context"

mkdir -p "$ROOT/dist"
cp "$WORKDIR/context/root.ext4" "$ROOT/dist/${system_name}.ext4"

echo "image $TAG"
echo "ref ghcr.io/egao1980/cl-microvm/${system_name}:${version}"
echo "ext4 $ROOT/dist/${system_name}.ext4"
