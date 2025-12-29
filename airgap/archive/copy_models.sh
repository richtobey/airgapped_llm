#!/usr/bin/env bash
set -euo pipefail

# Quick script to copy existing Ollama models to the bundle
# Use this if get_bundle.sh didn't copy models for some reason

BUNDLE_DIR="${BUNDLE_DIR:-$PWD/airgap_bundle}"

if [[ ! -d "$HOME/.ollama" ]]; then
  echo "ERROR: ~/.ollama directory does not exist"
  exit 1
fi

if [[ ! -d "$BUNDLE_DIR" ]]; then
  echo "ERROR: Bundle directory does not exist: $BUNDLE_DIR"
  exit 1
fi

echo "Copying models from ~/.ollama to $BUNDLE_DIR/models/.ollama..."
echo "This may take a while (models are ~49GB)..."

mkdir -p "$BUNDLE_DIR/models"

if rsync -av --progress "$HOME/.ollama/" "$BUNDLE_DIR/models/.ollama/"; then
  TOTAL_SIZE=$(du -sh "$BUNDLE_DIR/models/.ollama" 2>/dev/null | cut -f1 || echo "unknown")
  echo ""
  echo "✓ Models copied successfully!"
  echo "  Total size: $TOTAL_SIZE"
  echo "  Location: $BUNDLE_DIR/models/.ollama"
else
  echo "ERROR: Failed to copy models"
  exit 1
fi

