#!/bin/sh
# Assemble /rootfs from the SBCL install in this container. Run as root.
set -eu

SBCL_VERSION="${SBCL_VERSION:-2.6.7}"
TARGETARCH="${TARGETARCH:-amd64}"
case "$TARGETARCH" in
    amd64) SBCL_ARCH=x86-64 ;;
    arm64) SBCL_ARCH=arm64 ;;
    *) echo "unsupported TARGETARCH=$TARGETARCH" >&2; exit 1 ;;
esac

apt-get update
apt-get install -y --no-install-recommends \
    ca-certificates curl bzip2 build-essential
rm -rf /var/lib/apt/lists/*

cd /tmp
curl -fsSL -o sbcl.tar.bz2 \
    "https://github.com/roswell/sbcl_bin/releases/download/${SBCL_VERSION}/sbcl-${SBCL_VERSION}-${SBCL_ARCH}-linux-binary.tar.bz2"
tar -xf sbcl.tar.bz2
cd "/tmp/sbcl-${SBCL_VERSION}-${SBCL_ARCH}-linux"
INSTALL_ROOT=/usr/local sh install.sh

curl -fsSL -o /tmp/slime.tar.gz \
    https://github.com/slime/slime/archive/refs/tags/v2.31.tar.gz
mkdir -p /opt/swank
tar -xzf /tmp/slime.tar.gz -C /opt/swank --strip-components=1

gcc -static -Os -s -o /init /src/image/init.c

mkdir -p /rootfs/opt/cl-microvm /rootfs/opt/cl /rootfs/opt/app /rootfs/opt/cache \
    /rootfs/opt/swank /rootfs/data /rootfs/tmp /rootfs/proc /rootfs/sys /rootfs/dev \
    /rootfs/dev/shm /rootfs/run /rootfs/etc/ssl/certs /rootfs/usr
cp -a /usr/local /rootfs/usr/
cp -a /opt/swank/. /rootfs/opt/swank/
cp /init /rootfs/init
cp /src/image/boot.lisp /rootfs/opt/cl-microvm/boot.lisp
cp /src/image/nsswitch.conf /rootfs/etc/nsswitch.conf
cp /src/image/hosts /rootfs/etc/hosts
cp -L /etc/ssl/certs/ca-certificates.crt /rootfs/etc/ssl/certs/ca-certificates.crt
chmod 755 /rootfs/init
chmod 1777 /rootfs/opt/cache /rootfs/tmp
chown 65534:65534 /rootfs/data

copy_lib() {
    src=$1
    seen=" "
    while [ -n "$src" ]; do
        case "$seen" in
            *" $src "*) break ;;
        esac
        seen="$seen$src "
        if [ ! -e "$src" ] && [ ! -L "$src" ]; then
            echo "missing library: $src" >&2
            exit 1
        fi
        dest="/rootfs${src}"
        mkdir -p "$(dirname "$dest")"
        cp -a "$src" "$dest"
        if [ -L "$src" ]; then
            target=$(readlink "$src")
            case "$target" in
                /*) src=$target ;;
                *) src="$(dirname "$src")/$target" ;;
            esac
        else
            break
        fi
    done
}

# ldd prints the loader as a whitespace-indented absolute path, and shared
# objects after "=>". Take the first absolute path on each line.
ldd /usr/local/bin/sbcl | awk '{
    for (i = 1; i <= NF; i++) if ($i ~ /^\//) { print $i; break }
}' | while read -r lib; do
    copy_lib "$lib"
done

find /lib /usr/lib \( -name 'libnss_files.so*' -o -name 'libnss_dns.so*' -o -name 'libresolv.so*' \) |
    while read -r lib; do
        copy_lib "$lib"
    done

if [ -f /etc/ld.so.cache ]; then
    cp -a /etc/ld.so.cache /rootfs/etc/ld.so.cache
fi

# Absolute symlink targets (usrmerge /lib -> usr/lib) must exist in the guest.
# Skip proc/sys/dev; those are mounted at boot.
find /rootfs -type l | while read -r link; do
    target=$(readlink "$link")
    case "$target" in
        /proc/*|/sys/*|/dev/*) continue ;;
        /*) ;;
        *) continue ;;
    esac
    if [ ! -e "/rootfs${target}" ] && [ -e "$target" ]; then
        copy_lib "$target"
    fi
done

cat > /rootfs/etc/passwd <<'EOF'
root:x:0:0:root:/root:/sbin/nologin
lisp:x:65534:65534:lisp:/data:/sbin/nologin
EOF
cat > /rootfs/etc/group <<'EOF'
root:x:0:
lisp:x:65534:
EOF

mkdir -p /rootfs/opt/cache /tmp/home
XDG_CACHE_HOME=/rootfs/opt/cache HOME=/tmp/home \
    /usr/local/bin/sbcl --disable-debugger --non-interactive \
    --eval '(require :asdf)' \
    --eval '(asdf:initialize-source-registry (quote (:source-registry (:directory #p"/opt/swank/") :ignore-inherited-configuration)))' \
    --eval '(asdf:load-system "swank")' \
    --quit
chmod -R a+rX /rootfs/opt/cache /rootfs/opt/swank /rootfs/usr /rootfs/etc
chmod 1777 /rootfs/opt/cache

echo "rootfs bytes: $(du -sb /rootfs | awk '{print $1}')"
