# cl-microvm

Base image `cl-microvm:sbcl-2.6.7`: threaded SBCL 2.6.7, static `/init`, ext4-ready root, IPv4, Swank off unless `SWANK_PORT` is set.

`cl-microvm-packager` resolves one project with `cl-repository-client` inside the linux builder and emits a child image plus `dist/<system>.ext4`. Quicklisp fallback fails the pack.

```sh
scripts/build-image.sh
scripts/smoke.sh
scripts/emit-image.sh hello examples/hello
scripts/smoke-app.sh
```

Deps need `CL_REPOSITORY` (checkout of `egao1980/cl-repository`) and `QUICKLISP_SETUP` so the builder can load the client. The project closure itself is installed from `ghcr.io/egao1980/cl-systems` with `:default-source :oci`.

Guest env: `CL_SYSTEM`, `CL_ENTRY=package:function`, `SWANK_PORT`, `SWANK_INTERFACE` (default `0.0.0.0`), `SWANK_SECRET`. Packed images also write `CL_SYSTEM` to `/etc/cl-microvm.env` so the ext4 guest matches the container. Swank is slime v2.31 unpacked into the base image at build time.

Kernel: `scripts/build-kernel.sh`. aarch64 QEMU uses `-M virt` (`microvm` is x86_64-only). Console is `ttyAMA0` on aarch64 and `ttyS0` on x86_64. `scripts/boot-qemu.sh dist/hello.ext4`. Linux panics when PID 1 exits; `exitcode=0x00000000` is a clean Lisp shutdown.
