# Justfile recipes for managing the Oniro emulator locally.
#
# Consume from another repo via `import` (just 1.36+) once this repo is
# vendored as a submodule, e.g.:
#
#   # in your top-level justfile
#   import 'emulator-action/justfile'
#
# Then `just emulator` / `just emulator-stop` are available.
#
# `ONIRO_EMULATOR_PATH` must be exported by the caller (or set in the consumer
# justfile) — it points at the directory containing bzImage, ramdisk.img, ...

# Path to the scripts dir, resolved relative to *this* justfile so it keeps
# working when imported from another repo.
_emulator_script_dir := source_directory() / "scripts"

emulator_connect_key := "127.0.0.1:55555"

# Boot the Oniro emulator in the background and wait until hdc connects.
emulator connect_key=emulator_connect_key:
    bash {{ _emulator_script_dir }}/start-oniro-emulator.sh {{ connect_key }}

# Stop the emulator started via `just emulator`.
emulator-stop:
    bash {{ _emulator_script_dir }}/stop-oniro-emulator.sh

# Run the qemu launcher in the foreground (no pid tracking, no hdc wait).
# Useful for debugging boot output. Requires ONIRO_EMULATOR_PATH.
emulator-foreground connect_key=emulator_connect_key:
    bash {{ _emulator_script_dir }}/oniro-emulator-run.sh "$ONIRO_EMULATOR_PATH" {{ connect_key }}
