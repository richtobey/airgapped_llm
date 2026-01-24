#!/usr/bin/env bash
# Network interface restore script
# This script restores network interfaces that were disabled during airgapped installation
# 
# Usage:
#   sudo ./restore_network.sh [network_state_dir]
#
# If no directory is specified, it will look for network_state/ in the current directory
# or in the airgap_bundle directory

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if running as root or with sudo
if [[ $EUID -ne 0 ]]; then
  echo -e "${RED}ERROR: This script must be run as root or with sudo${NC}" >&2
  echo "Usage: sudo $0 [network_state_dir]" >&2
  exit 1
fi

# Determine network state directory
if [[ -n "$1" ]]; then
  NETWORK_STATE_DIR="$1"
elif [[ -d "./network_state" ]]; then
  NETWORK_STATE_DIR="./network_state"
elif [[ -d "./airgap_bundle/network_state" ]]; then
  NETWORK_STATE_DIR="./airgap_bundle/network_state"
elif [[ -d "$HOME/airgap_bundle/network_state" ]]; then
  NETWORK_STATE_DIR="$HOME/airgap_bundle/network_state"
else
  echo -e "${RED}ERROR: Network state directory not found${NC}" >&2
  echo "Please specify the network_state directory:" >&2
  echo "  sudo $0 /path/to/network_state" >&2
  exit 1
fi

NETWORK_STATE_FILE="${NETWORK_STATE_DIR}/disabled_interfaces.txt"
RESTORE_SCRIPT="${NETWORK_STATE_DIR}/restore_network.sh"

echo "=========================================="
echo "Network Interface Restore"
echo "=========================================="
echo ""
echo "Network state directory: $NETWORK_STATE_DIR"
echo ""

# Check if state file exists
if [[ ! -f "$NETWORK_STATE_FILE" ]]; then
  echo -e "${YELLOW}WARNING: Network state file not found: $NETWORK_STATE_FILE${NC}"
  echo "This may mean no interfaces were disabled during installation."
  echo ""
  
  # Try to use the generated restore script if it exists
  if [[ -f "$RESTORE_SCRIPT" ]]; then
    echo "Found restore script: $RESTORE_SCRIPT"
    echo "Executing restore script..."
    echo ""
    bash "$RESTORE_SCRIPT"
    exit $?
  else
    echo -e "${RED}ERROR: No restore script found either${NC}"
    exit 1
  fi
fi

# Display what was disabled
echo "Interfaces that were disabled:"
echo "---"
grep "^=== Interface:" "$NETWORK_STATE_FILE" | sed 's/^=== Interface: /  - /' | sed 's/ ===$//'
echo ""

# Ask for confirmation
read -r -p "Do you want to restore these network interfaces? (yes/no): " RESTORE_CONFIRM
if [[ ! "$RESTORE_CONFIRM" =~ ^[Yy](es)?$ ]]; then
  echo "Restore cancelled."
  exit 0
fi

echo ""
echo "Restoring network interfaces..."
echo ""

# Use the generated restore script if it exists
if [[ -f "$RESTORE_SCRIPT" ]]; then
  echo "Using generated restore script: $RESTORE_SCRIPT"
  echo ""
  bash "$RESTORE_SCRIPT"
  RESTORE_EXIT=$?
else
  # Fallback: manual restoration based on state file
  echo -e "${YELLOW}WARNING: Restore script not found. Attempting manual restoration...${NC}"
  echo ""
  
  # Extract interface names from state file
  INTERFACES=$(grep "^=== Interface:" "$NETWORK_STATE_FILE" | sed 's/^=== Interface: //' | sed 's/ ===$//')
  
  RESTORED_COUNT=0
  for iface in $INTERFACES; do
    [[ -z "$iface" ]] && continue
    
    echo "Restoring interface: $iface"
    
    # Bring interface up
    if ip link set "$iface" up 2>/dev/null; then
      echo -e "  ${GREEN}✓${NC} Interface $iface brought up"
      ((RESTORED_COUNT++))
    else
      echo -e "  ${RED}✗${NC} Failed to bring up interface $iface"
    fi
  done
  
  echo ""
  echo "=========================================="
  if [[ $RESTORED_COUNT -gt 0 ]]; then
    echo -e "${GREEN}Network restoration complete${NC}"
    echo "Restored $RESTORED_COUNT interface(s)"
    RESTORE_EXIT=0
  else
    echo -e "${RED}Network restoration failed${NC}"
    RESTORE_EXIT=1
  fi
  echo "=========================================="
fi

echo ""
echo "Note: You may need to restart network services for full functionality:"
echo "  sudo systemctl restart NetworkManager"
echo "  sudo systemctl restart systemd-networkd"
echo ""

exit $RESTORE_EXIT
