#!/usr/bin/env bash
# Script to safely configure passwordless sudo for the current user
# This is required for get_bundle.sh to build the APT repository

set -e

# Get current user
CURRENT_USER="${SUDO_USER:-$USER}"
if [[ -z "$CURRENT_USER" ]]; then
  echo "ERROR: Could not determine current user" >&2
  exit 1
fi

# Check if already configured
if sudo -n true 2>/dev/null; then
  echo "✓ Passwordless sudo is already configured for $CURRENT_USER"
  exit 0
fi

echo "Configuring passwordless sudo for user: $CURRENT_USER"
echo ""
echo "This will add the following line to /etc/sudoers:"
echo "  $CURRENT_USER ALL=(ALL) NOPASSWD: ALL"
echo ""
read -p "Continue? (yes/no): " CONFIRM

if [[ ! "$CONFIRM" =~ ^[Yy](es)?$ ]]; then
  echo "Aborted."
  exit 1
fi

# Check if user is in sudo group
if groups "$CURRENT_USER" | grep -q "\bsudo\b"; then
  echo "User $CURRENT_USER is in the 'sudo' group."
  echo "Adding group-based rule (safer for multi-user systems)..."
  SUDOERS_LINE="%sudo ALL=(ALL) NOPASSWD: ALL"
else
  echo "User $CURRENT_USER is not in the 'sudo' group."
  echo "Adding user-specific rule..."
  SUDOERS_LINE="$CURRENT_USER ALL=(ALL) NOPASSWD: ALL"
fi

# Create a temporary sudoers file with the new rule
TMP_SUDOERS=$(mktemp)
trap "rm -f $TMP_SUDOERS" EXIT

# Check if the rule already exists
if sudo grep -q "^${SUDOERS_LINE}$" /etc/sudoers 2>/dev/null || \
   sudo grep -q "^${SUDOERS_LINE//\//\\/}$" /etc/sudoers 2>/dev/null; then
  echo "✓ Passwordless sudo rule already exists in /etc/sudoers"
  exit 0
fi

# Copy current sudoers and add new rule
sudo cp /etc/sudoers "$TMP_SUDOERS"
echo "" >> "$TMP_SUDOERS"
echo "# Passwordless sudo for $CURRENT_USER (added by setup_passwordless_sudo.sh)" >> "$TMP_SUDOERS"
echo "$SUDOERS_LINE" >> "$TMP_SUDOERS"

# Validate the sudoers file syntax
if ! sudo visudo -cf "$TMP_SUDOERS" 2>/dev/null; then
  echo "ERROR: Generated sudoers file has syntax errors. Aborting." >&2
  exit 1
fi

# Install the new sudoers file
sudo cp "$TMP_SUDOERS" /etc/sudoers
sudo chmod 0440 /etc/sudoers

echo ""
echo "✓ Passwordless sudo configured successfully!"
echo ""
echo "Verifying configuration..."
if sudo -n true 2>/dev/null; then
  echo "✓ Verification successful - passwordless sudo is working"
else
  echo "WARNING: Verification failed. You may need to log out and back in."
  echo "Try running: sudo -n true"
fi
