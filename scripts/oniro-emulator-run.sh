#!/usr/bin/env bash
#
# Launch the Oniro QEMU emulator.
#
# Auto-detects host acceleration (KVM on Linux, HVF on macOS/x86_64) and audio
# backends. Override via the env vars below if you want to force a particular
# configuration.
#
# Environment variables:
#   ONIRO_EMULATOR_QEMU      QEMU binary to invoke (default: qemu-system-x86_64).
#   ONIRO_EMULATOR_ACCEL     auto|kvm|hvf|tcg (default: auto).
#   ONIRO_EMULATOR_AUDIO     auto|none|<backend> where <backend> is a name
#                            accepted by `-audiodev`, e.g. pa, alsa,
#                            coreaudio, dsound, sdl (default: auto).
#   ONIRO_EMULATOR_SMP       Number of vCPUs (default: 4).
#   ONIRO_EMULATOR_MEMORY    Guest memory size, qemu syntax (default: 4096M).

set -euo pipefail

image_dir="${1:-}"
connect_key="${2:-127.0.0.1:55555}"

if [ -z "$image_dir" ]; then
  echo "Usage: $0 <oniro-emulator-images-dir> [host:port]" >&2
  exit 1
fi

if [[ "$connect_key" != *:* ]]; then
  echo "Error: expected connect key in host:port form, got '$connect_key'." >&2
  exit 1
fi

forward_host="${connect_key%:*}"
forward_port="${connect_key##*:}"

if [ -z "$forward_host" ] || [ -z "$forward_port" ]; then
  echo "Error: expected connect key in host:port form, got '$connect_key'." >&2
  exit 1
fi

if [[ ! "$forward_port" =~ ^[0-9]+$ ]]; then
  echo "Error: expected numeric port in connect key, got '$connect_key'." >&2
  exit 1
fi

qemu_bin="${ONIRO_EMULATOR_QEMU:-qemu-system-x86_64}"

if ! command -v "$qemu_bin" >/dev/null 2>&1; then
  echo "Error: $qemu_bin is not available on PATH. Install QEMU and retry." >&2
  exit 1
fi

required_files=(
  "bzImage"
  "ramdisk.img"
  "updater.img"
  "system.img"
  "vendor.img"
  "userdata.img"
)

for required_file in "${required_files[@]}"; do
  if [ ! -f "$image_dir/$required_file" ]; then
    echo "Error: expected $image_dir/$required_file" >&2
    exit 1
  fi
done

# --- Acceleration ----------------------------------------------------------

accel_arg=()
cpu_arg=()
host_os="$(uname -s)"
host_arch="$(uname -m)"
accel_choice="${ONIRO_EMULATOR_ACCEL:-auto}"

select_kvm() {
  if [ ! -e /dev/kvm ]; then
    return 1
  fi
  if [ ! -r /dev/kvm ] || [ ! -w /dev/kvm ]; then
    echo "Note: /dev/kvm exists but is not accessible. Add your user to the kvm group for hardware acceleration." >&2
    return 1
  fi
  accel_arg=(-enable-kvm)
  cpu_arg=(-cpu host)
  return 0
}

select_hvf() {
  accel_arg=(-accel hvf)
  cpu_arg=(-cpu host)
}

select_tcg() {
  accel_arg=(-accel tcg,thread=multi)
  cpu_arg=(-cpu max)
}

case "$accel_choice" in
  auto)
    case "$host_os" in
      Linux)
        if ! select_kvm; then
          echo "Note: KVM unavailable, falling back to TCG. Boot will be slow." >&2
          select_tcg
        fi
        ;;
      Darwin)
        if [ "$host_arch" = "x86_64" ]; then
          select_hvf
        else
          # HVF can't run x86_64 guests on Apple Silicon.
          select_tcg
        fi
        ;;
      *)
        echo "Note: unsupported host OS '$host_os' for auto-accel, falling back to TCG." >&2
        select_tcg
        ;;
    esac
    ;;
  kvm)
    if ! select_kvm; then
      echo "Error: ONIRO_EMULATOR_ACCEL=kvm requested but /dev/kvm is unavailable." >&2
      exit 1
    fi
    ;;
  hvf)
    select_hvf
    ;;
  tcg)
    select_tcg
    ;;
  *)
    echo "Error: unknown ONIRO_EMULATOR_ACCEL '$accel_choice' (expected auto|kvm|hvf|tcg)." >&2
    exit 1
    ;;
esac

# --- Audio -----------------------------------------------------------------

audio_args=()
audio_choice="${ONIRO_EMULATOR_AUDIO:-auto}"

# Returns the first backend in `preferred` that QEMU was built with, or 1 on
# no match. `qemu -audiodev help` prints one backend per line on a recent
# QEMU; we match each line as a whole word.
probe_audio_backend() {
  local available
  available="$("$qemu_bin" -audiodev help 2>/dev/null || true)"
  if [ -z "$available" ]; then
    return 1
  fi
  local backend
  for backend in "$@"; do
    if printf '%s\n' "$available" | grep -qx "$backend"; then
      printf '%s' "$backend"
      return 0
    fi
  done
  return 1
}

case "$audio_choice" in
  none)
    ;;
  auto)
    # Prefer a real backend, but fall back to `none` so the es1370 device is
    # still present and the guest's audio probe finds it (matches hdc-py's
    # local behaviour). If even `none` is unavailable, omit audio entirely.
    if backend="$(probe_audio_backend pa alsa coreaudio dsound sdl oss none)"; then
      audio_args=(-audiodev "${backend},id=audio0" -device es1370,audiodev=audio0)
    fi
    ;;
  *)
    audio_args=(-audiodev "${audio_choice},id=audio0" -device es1370,audiodev=audio0)
    ;;
esac

# --- Misc ------------------------------------------------------------------

smp="${ONIRO_EMULATOR_SMP:-4}"
memory="${ONIRO_EMULATOR_MEMORY:-4096M}"

cd "$image_dir"

exec "$qemu_bin" \
  -machine q35 \
  -smp "$smp" \
  -m "$memory" \
  -boot c \
  -nographic \
  -rtc base=utc,clock=host \
  -initrd ramdisk.img \
  -kernel bzImage \
  -drive if=none,file=updater.img,format=raw,id=updater,index=0 \
  -device virtio-blk-pci,drive=updater \
  -drive if=none,file=system.img,format=raw,id=system,index=1 \
  -device virtio-blk-pci,drive=system \
  -drive if=none,file=vendor.img,format=raw,id=vendor,index=2 \
  -device virtio-blk-pci,drive=vendor \
  -drive if=none,file=userdata.img,format=raw,id=userdata,index=3 \
  -device virtio-blk-pci,drive=userdata \
  -append "ip=dhcp loglevel=4 console=ttyS0,115200 init=init root=/dev/ram0 rw ohos.boot.hardware=x86_general ohos.required_mount.system=/dev/block/vdb@/usr@ext4@ro,barrier=1@wait,required ohos.required_mount.vendor=/dev/block/vdc@/vendor@ext4@ro,barrier=1@wait,required ohos.required_mount.misc=/dev/block/vda@/misc@none@none=@wait,required" \
  "${accel_arg[@]}" \
  "${cpu_arg[@]}" \
  "${audio_args[@]}" \
  -netdev "user,id=net0,hostfwd=tcp:${forward_host}:${forward_port}-:55555" \
  -device virtio-net-pci,netdev=net0
