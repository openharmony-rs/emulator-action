# Oniro Emulator Action

A GitHub composite action that boots the [Oniro](https://github.com/eclipse-oniro4openharmony/device_board_oniro)
QEMU emulator on a Linux runner and waits until an `hdc` target is available.
Oniro is an OpenHarmony distribution under the Eclipse foundation in cooperation with the OpenAtom Foundation.

Use the action to run tests on OpenHarmony in CI. Currently only `x86_64` images are available, so you will need to compile your code for `x86_64-unknown-linux-ohos`.

This repo also ships the same launcher as standalone shell scripts and a `justfile`,
so the local-developer flow (`just emulator` / `just emulator-stop`) and the CI
flow share a single qemu invocation.

## Requirements

- A Linux runner (`ubuntu-latest` is fine).
- `hdc` on `PATH` before this action runs. The simplest way is
  [`openharmony-rs/setup-ohos-sdk`](https://github.com/openharmony-rs/setup-ohos-sdk),
  which exposes `hdc` via the SDK's `toolchains/` directory.

## CI usage

```yaml
- name: Setup OpenHarmony SDK (provides hdc)
  id: setup_sdk
  uses: openharmony-rs/setup-ohos-sdk@v1.0.0
  with:
    version: 6.1

- name: Add OHOS toolchains to PATH
  run: echo "$(dirname "${OHOS_SDK_NATIVE}")/toolchains" >> "$GITHUB_PATH"
  env:
    OHOS_SDK_NATIVE: ${{ steps.setup_sdk.outputs.ohos_sdk_native }}

- name: Start Oniro emulator
  uses: openharmony-rs/emulator-action@v1

- name: Run something against the emulator
  run: hdc shell echo hello-world
```

### Inputs

| Name                  | Default                  | Description                                                          |
| --------------------- | ------------------------ | -------------------------------------------------------------------- |
| `release`             | `v6.1`                   | Release tag in `eclipse-oniro4openharmony/device_board_oniro`.       |
| `asset`               | `oniro_emulator.zip`     | Asset filename to download from that release.                        |
| `connect-key`         | `127.0.0.1:55555`        | `host:port` the emulator will be reachable on via hdc.               |
| `cache`               | `true`                   | Whether to cache the downloaded archive between runs.                |
| `log-path`            | `/tmp/oniro-emulator.log`| Where to redirect emulator stdout/stderr.                            |
| `port-wait-seconds`   | `120`                    | Seconds to wait for the hostfwd port to become reachable.            |
| `hdc-wait-seconds`    | `120`                    | Seconds to wait for `hdc tconn` to succeed after the port is up.     |
| `accel`               | `auto`                   | QEMU acceleration: `auto` / `kvm` / `hvf` / `tcg`.                   |
| `audio`               | `none`                   | Audio config: `auto` / `none` / explicit qemu audiodev backend.      |
| `smp`                 | `4`                      | Guest vCPU count.                                                    |
| `memory`              | `4096M`                  | Guest memory size (qemu syntax).                                     |

### Outputs

| Name          | Description                                  |
| ------------- | -------------------------------------------- |
| `log-path`    | Path to the emulator log file.               |
| `connect-key` | `host:port` the emulator is reachable on.    |

### Uploading the emulator log on failure

Composite actions cannot run a `post:` step, so add an `if: always()` upload
step yourself when you want the log preserved on failure:

```yaml
- name: Upload emulator log
  if: always()
  uses: actions/upload-artifact@v7
  with:
    name: oniro-emulator-log
    path: /tmp/oniro-emulator.log
```

## Local usage (justfile import)

Vendor this repo into your own project as a submodule:

```bash
git submodule add https://github.com/openharmony-rs/emulator-action.git emulator-action
```

Then `import` the bundled justfile from your top-level `justfile`:

```just
import 'emulator-action/justfile'

# (optional) point the recipes at your extracted images directory
export ONIRO_EMULATOR_PATH := "/path/to/extracted/oniro_emulator"
```

That gives you:

- `just emulator` — boots the emulator in the background, retries up to 10
  ports above the requested one if the default `127.0.0.1:55555` is busy,
  and waits for `hdc tconn` to succeed.
- `just emulator-stop` — terminates the previously started qemu process.
- `just emulator-foreground` — runs the launcher in the foreground for debugging.

The connect key picked at boot is written to `/tmp/oniro-emulator.connect`,
the pid to `/tmp/oniro-emulator.pid`, and the qemu log to `/tmp/oniro-emulator.log`.

### Direct script use (without just)

If you don't use `just`, the same scripts work directly:

```bash
ONIRO_EMULATOR_PATH=/path/to/images \
  ./emulator-action/scripts/start-oniro-emulator.sh 127.0.0.1:55555
# ... do work ...
./emulator-action/scripts/stop-oniro-emulator.sh
```

### Acceleration and audio auto-detection

The launcher (`scripts/oniro-emulator-run.sh`) probes the host on each invocation:

- **Acceleration**: `-enable-kvm -cpu host` on Linux when `/dev/kvm` is
  readable+writable; `-accel hvf -cpu host` on macOS x86_64; `-accel tcg
  -cpu max` everywhere else (including macOS aarch64 and CI runners without
  KVM).
- **Audio**: queries `qemu -audiodev help` and picks the first available
  real backend (`pa`, `alsa`, `coreaudio`, `dsound`, `sdl`, `oss`), falling
  back to the `none` backend so the `es1370` device is still presented to
  the guest. CI defaults to `audio=none` to skip the device entirely.

Override via env vars:

| Variable                | Values                                  |
| ----------------------- | --------------------------------------- |
| `ONIRO_EMULATOR_QEMU`   | qemu binary (default `qemu-system-x86_64`) |
| `ONIRO_EMULATOR_ACCEL`  | `auto` / `kvm` / `hvf` / `tcg`          |
| `ONIRO_EMULATOR_AUDIO`  | `auto` / `none` / qemu audiodev backend |
| `ONIRO_EMULATOR_SMP`    | vCPU count (default `4`)                |
| `ONIRO_EMULATOR_MEMORY` | qemu memory string (default `4096M`)    |

## License

Apache-2.0. See [LICENSE](LICENSE).
