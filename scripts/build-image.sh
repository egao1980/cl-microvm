#!/bin/bash
# Build the base runtime image and the packager builder image.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
docker build -f image/Dockerfile --target builder -t cl-microvm:builder .
docker build -f image/Dockerfile --target runtime -t cl-microvm:sbcl-2.6.7 .
