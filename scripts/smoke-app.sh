#!/bin/bash
# Boot an emitted app image with network disabled. Expects hello:main.
set -euo pipefail
IMAGE="${1:-cl-microvm-app:hello-0.1.0}"
out="$(docker run --rm --network none -e CL_ENTRY=hello:main "$IMAGE")"
printf '%s\n' "$out"
printf '%s\n' "$out" | grep -qx 'hello-ok'
echo app-ok
