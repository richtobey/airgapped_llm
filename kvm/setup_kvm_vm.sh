#!/bin/bash
# Set up KVM VM from converted disk image
# Creates VM with appropriate configuration for System76

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

# Default configuration
VM_NAME=""
VM_DISK=""
VM_MEMORY="${VM_MEMORY:-4096}"  # 4GB default
VM_CPUS="${VM_CPUS:-2}"
VM_NETWORK="${VM_NETWORK:-default}"  # default NAT network
VM_GRAPHICS="${VM_GRAPHICS:-spice}"  # spice or vnc
VM_VIDEO="${VM_VIDEO:-qxl}"  # qxl or virtio

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --name|-n)
            VM_NAME="$2"
            shift 2
            ;;
        --disk|-d)
            VM_DISK="$2"
            shift 2
            ;;
        --memory|-m)
            VM_MEMORY="$2"
            shift 2
            ;;
        --cpus|-c)
            VM_CPUS="$2"
            shift 2
            ;;
        --network)
            VM_NETWORK="$2"
            shift 2
            ;;
        --graphics)
            VM_GRAPHICS="$2"
            shift 2
            ;;
        --video)
            VM_VIDEO="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 VM_NAME VM_DISK [OPTIONS]"
            echo ""
            echo "Arguments:"
            echo "  VM_NAME       Name for the VM"
            echo "  VM_DISK       Path to VM disk image (.qcow2)"
            echo ""
            echo "Options:"
            echo "  -m, --memory SIZE    Memory in MB (default: 4096)"
            echo "  -c, --cpus COUNT     CPU count (default: 2)"
            echo "  --network NAME       Network name (default: default)"
            echo "  --graphics TYPE      Graphics type: spice or vnc (default: spice)"
            echo "  --video TYPE         Video type: qxl or virtio (default: qxl)"
            echo ""
            echo "Example:"
            echo "  $0 popos-vm /var/lib/libvirt/images/popos-vm.qcow2 --memory 8192 --cpus 4"
            exit 0
            ;;
        *)
            if [[ -z "$VM_NAME" ]]; then
                VM_NAME="$1"
            elif [[ -z "$VM_DISK" ]]; then
                VM_DISK="$1"
            else
                error "Unknown argument: $1"
            fi
            shift
            ;;
    esac
done

# Validate arguments
if [[ -z "$VM_NAME" ]] || [[ -z "$VM_DISK" ]]; then
    error "Usage: $0 VM_NAME VM_DISK [OPTIONS]"
fi

# Check prerequisites
if ! command -v virsh >/dev/null 2>&1; then
    error "virsh not found. Install libvirt: sudo apt-get install libvirt-clients"
fi

if ! command -v virt-install >/dev/null 2>&1; then
    error "virt-install not found. Install: sudo apt-get install virtinst"
fi

# Check if running as root or with sudo
if [[ $EUID -ne 0 ]]; then
    warn "Not running as root. Some operations may require sudo."
    SUDO="sudo"
else
    SUDO=""
fi

# Check if VM already exists
if virsh dominfo "$VM_NAME" >/dev/null 2>&1; then
    error "VM '$VM_NAME' already exists. Remove it first: virsh undefine $VM_NAME"
fi

# Check if disk exists
if [[ ! -f "$VM_DISK" ]]; then
    error "VM disk not found: $VM_DISK"
fi

# Get disk info
DISK_SIZE=$(du -h "$VM_DISK" | cut -f1)
info "VM Name: $VM_NAME"
info "VM Disk: $VM_DISK ($DISK_SIZE)"
info "Memory: ${VM_MEMORY}MB"
info "CPUs: $VM_CPUS"
info "Network: $VM_NETWORK"
info "Graphics: $VM_GRAPHICS"

# Check KVM support
if [[ ! -c /dev/kvm ]]; then
    warn "KVM device not found. VM will use software emulation (slower)."
    warn "Enable KVM in BIOS/UEFI and ensure /dev/kvm exists."
else
    info "KVM acceleration: Available"
fi

# Check network exists
if ! virsh net-info "$VM_NETWORK" >/dev/null 2>&1; then
    warn "Network '$VM_NETWORK' not found. Creating default network..."
    $SUDO virsh net-define /usr/share/libvirt/networks/default.xml 2>/dev/null || true
    $SUDO virsh net-start default 2>/dev/null || true
    $SUDO virsh net-autostart default 2>/dev/null || true
fi

# Create VM using virt-install
info "Creating VM..."

# Build virt-install command
INSTALL_CMD=(
    virt-install
    --name "$VM_NAME"
    --ram "$VM_MEMORY"
    --vcpus "$VM_CPUS"
    --disk "path=$VM_DISK,format=qcow2,bus=virtio"
    --network "network=$VM_NETWORK"
    --graphics "$VM_GRAPHICS,listen=0.0.0.0"
    --video "$VM_VIDEO"
    --import
    --noautoconsole
    --os-type linux
    --os-variant popos22.04
)

# Add additional options based on graphics type
if [[ "$VM_GRAPHICS" == "spice" ]]; then
    INSTALL_CMD+=(--channel spicevmc)
    INSTALL_CMD+=(--channel unix,name=org.qemu.guest_agent.0)
fi

# Execute virt-install
if $SUDO "${INSTALL_CMD[@]}"; then
    info "VM created successfully!"
else
    error "Failed to create VM"
fi

# Wait a moment for VM to be defined
sleep 2

# Get VM info
info ""
info "VM Information:"
virsh dominfo "$VM_NAME" || true

# Display connection info
info ""
info "VM created successfully!"
info ""
info "To start the VM:"
info "  virsh start $VM_NAME"
info ""
info "To view the console:"
if [[ "$VM_GRAPHICS" == "spice" ]]; then
    info "  virt-viewer $VM_NAME"
    info "  Or use: spicec -h localhost -p $(virsh domdisplay $VM_NAME | cut -d: -f2)"
elif [[ "$VM_GRAPHICS" == "vnc" ]]; then
    info "  virt-viewer $VM_NAME"
    info "  Or use VNC client: $(virsh domdisplay $VM_NAME)"
fi
info ""
info "To access via console:"
info "  virsh console $VM_NAME"
info ""
info "To manage the VM:"
info "  virsh list --all"
info "  virsh edit $VM_NAME"
info "  virt-manager  # GUI management"
info ""
info "Post-migration steps:"
info "  1. Start VM: virsh start $VM_NAME"
info "  2. Install SPICE guest tools (inside VM):"
info "     sudo apt-get install spice-vdagent spice-webdavd"
info "  3. Reboot VM: virsh reboot $VM_NAME"
info "  4. Verify network and services"

