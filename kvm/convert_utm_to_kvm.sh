#!/bin/bash
# Convert UTM disk image to KVM-compatible format
# Optimizes disk format and ensures compatibility

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

error() {
    echo -e "${RED}ERROR: $*${NC}" >&2
    exit 1
}

info() {
    echo -e "${GREEN}INFO: $*${NC}"
}

warn() {
    echo -e "${YELLOW}WARN: $*${NC}"
}

# Parse arguments
INPUT_DISK=""
OUTPUT_DISK=""
OPTIMIZE=false
COMPRESS=false
FORCE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --output|-o)
            OUTPUT_DISK="$2"
            shift 2
            ;;
        --optimize)
            OPTIMIZE=true
            shift
            ;;
        --compress)
            COMPRESS=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --help)
            echo "Usage: $0 INPUT_DISK [OPTIONS]"
            echo ""
            echo "Arguments:"
            echo "  INPUT_DISK    Path to UTM disk image (.qcow2)"
            echo ""
            echo "Options:"
            echo "  -o, --output PATH    Output disk path (default: INPUT_DISK.kvm)"
            echo "  --optimize           Optimize disk for better performance"
            echo "  --compress           Compress disk to save space"
            echo "  --force              Overwrite existing output file"
            echo ""
            echo "Example:"
            echo "  $0 /path/to/utm-disk.qcow2 --optimize"
            exit 0
            ;;
        *)
            if [[ -z "$INPUT_DISK" ]]; then
                INPUT_DISK="$1"
            else
                error "Unknown argument: $1"
            fi
            shift
            ;;
    esac
done

# Validate arguments
if [[ -z "$INPUT_DISK" ]]; then
    error "Usage: $0 INPUT_DISK [OPTIONS]"
fi

# Check if input exists
if [[ ! -f "$INPUT_DISK" ]]; then
    error "Input disk not found: $INPUT_DISK"
fi

# Check for qemu-img
if ! command -v qemu-img >/dev/null 2>&1; then
    error "qemu-img not found. Install qemu-utils: sudo apt-get install qemu-utils"
fi

# Determine output path
if [[ -z "$OUTPUT_DISK" ]]; then
    OUTPUT_DISK="${INPUT_DISK%.*}.kvm.qcow2"
    # If input already has .kvm, use different suffix
    if [[ "$OUTPUT_DISK" == "$INPUT_DISK" ]]; then
        OUTPUT_DISK="${INPUT_DISK}.kvm"
    fi
fi

# Check if output exists
if [[ -f "$OUTPUT_DISK" ]] && [[ "$FORCE" != "true" ]]; then
    error "Output file exists: $OUTPUT_DISK (use --force to overwrite)"
fi

# Get disk info
info "Input disk: $INPUT_DISK"
INPUT_INFO=$(qemu-img info "$INPUT_DISK")
INPUT_FORMAT=$(echo "$INPUT_INFO" | grep -E "^file format:" | awk '{print $3}')
INPUT_SIZE=$(echo "$INPUT_INFO" | grep -E "^virtual size:" | awk '{print $3, $4}')
INPUT_ACTUAL=$(du -h "$INPUT_DISK" | cut -f1)

info "Input format: $INPUT_FORMAT"
info "Input size: $INPUT_SIZE"
info "Input actual size: $INPUT_ACTUAL"

# Check available space
OUTPUT_DIR=$(dirname "$OUTPUT_DISK")
AVAILABLE_SPACE=$(df -h "$OUTPUT_DIR" | tail -1 | awk '{print $4}')
info "Available space: $AVAILABLE_SPACE"

# Convert disk
info "Converting disk to KVM format..."
info "Output: $OUTPUT_DISK"

# Build qemu-img convert command
CONVERT_OPTS=("-f" "$INPUT_FORMAT" "-O" "qcow2")

if [[ "$OPTIMIZE" == "true" ]]; then
    info "Optimizing disk (this may take a while)..."
    CONVERT_OPTS+=("-o" "preallocation=metadata")
fi

if [[ "$COMPRESS" == "true" ]]; then
    info "Compressing disk (this may take a while)..."
    CONVERT_OPTS+=("-o" "compression_type=zlib")
fi

# Perform conversion
if qemu-img convert "${CONVERT_OPTS[@]}" "$INPUT_DISK" "$OUTPUT_DISK"; then
    info "Conversion completed successfully!"
else
    error "Conversion failed"
fi

# Verify output
OUTPUT_INFO=$(qemu-img info "$OUTPUT_DISK")
OUTPUT_FORMAT=$(echo "$OUTPUT_INFO" | grep -E "^file format:" | awk '{print $3}')
OUTPUT_SIZE=$(echo "$OUTPUT_INFO" | grep -E "^virtual size:" | awk '{print $3, $4}')
OUTPUT_ACTUAL=$(du -h "$OUTPUT_DISK" | cut -f1)

info "Output format: $OUTPUT_FORMAT"
info "Output size: $OUTPUT_SIZE"
info "Output actual size: $OUTPUT_ACTUAL"

# Check disk integrity
info "Checking disk integrity..."
if qemu-img check "$OUTPUT_DISK" >/dev/null 2>&1; then
    info "Disk integrity: OK"
else
    warn "Disk check found issues (may be normal for some disk types)"
fi

# Set permissions
chmod 644 "$OUTPUT_DISK" 2>/dev/null || true

info ""
info "Conversion complete!"
info "Converted disk: $OUTPUT_DISK"
info ""
info "Next steps:"
info "  ./setup_kvm_vm.sh popos-vm $OUTPUT_DISK"

