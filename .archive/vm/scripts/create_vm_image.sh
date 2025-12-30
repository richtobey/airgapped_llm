#!/usr/bin/env bash
set -euo pipefail

# Helper script to create VM disk image
# Usage: create_vm_image.sh <size> <output_path>

SIZE="${1:-50G}"
OUTPUT="${2:-popos-airgap.qcow2}"

log() { echo "[$(date -Is)] $*"; }

if ! command -v qemu-img >/dev/null 2>&1; then
  log "ERROR: qemu-img not found. Please install QEMU first."
  exit 1
fi

log "Creating VM disk image: $OUTPUT (size: $SIZE)"
qemu-img create -f qcow2 "$OUTPUT" "$SIZE"

log "VM disk image created: $OUTPUT"
log "Actual size on disk (sparse): $(du -h "$OUTPUT" | cut -f1)"

