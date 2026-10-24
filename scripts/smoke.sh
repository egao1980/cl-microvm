#!/bin/bash
# Boot the base image and require threads-ok, fs-ok, net-ok.
# With SWANK_PORT set, also require a TCP accept on that port.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IMAGE="${1:-cl-microvm:sbcl-2.6.7}"

port_file="$(mktemp)"
python3 - "$port_file" <<'PY' &
import socket, sys
path = sys.argv[1]
sock = socket.socket()
sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
sock.bind(("0.0.0.0", 0))
port = sock.getsockname()[1]
open(path, "w").write(str(port))
sock.listen(1)
conn, _ = sock.accept()
conn.close()
sock.close()
PY
listener=$!
trap 'kill "$listener" 2>/dev/null || true; rm -f "$port_file"' EXIT
for _ in 1 2 3 4 5 6 7 8 9 10; do
    [[ -s "$port_file" ]] && break
    sleep 0.1
done
port="$(cat "$port_file")"

out="$(docker run --rm \
    --add-host=host.docker.internal:host-gateway \
    -e CL_MICROVM_PROBE_HOST=host.docker.internal \
    -e CL_MICROVM_PROBE_PORT="$port" \
    "$IMAGE")"
printf '%s\n' "$out"
printf '%s\n' "$out" | grep -qx 'threads-ok'
printf '%s\n' "$out" | grep -qx 'fs-ok'
printf '%s\n' "$out" | grep -qx 'net-ok'
wait "$listener"

swank_out="$(mktemp)"
docker run -d --name cl-microvm-swank \
    -p 127.0.0.1:4005:4005 \
    -e SWANK_PORT=4005 \
    -e SWANK_SECRET=smoke-secret \
    "$IMAGE" >/dev/null
trap 'docker rm -f cl-microvm-swank >/dev/null 2>&1 || true; rm -f "$port_file" "$swank_out"' EXIT
ok=0
for _ in $(seq 1 30); do
    if docker logs cl-microvm-swank 2>&1 | tee "$swank_out" | grep -q 'swank-port 4005'; then
        ok=1
        break
    fi
    sleep 1
done
[[ "$ok" == 1 ]]
grep -q 'swank-secret smoke-secret' "$swank_out"
python3 - <<'PY'
import socket
s = socket.create_connection(("127.0.0.1", 4005), 5)
s.close()
PY
docker rm -f cl-microvm-swank >/dev/null
echo smoke-ok
