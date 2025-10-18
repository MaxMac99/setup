#!/usr/bin/env bash
set -euo pipefail

# Build NixOS image for k3s template
# This script ONLY builds the image, does not deploy to Proxmox

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Configuration - use user's home by default, can override with OUTPUT_DIR env var
OUTPUT_DIR="${OUTPUT_DIR:-$HOME/nixos-k3s-template}"

main() {
    log_info "========================================"
    log_info "Building NixOS K3S Image"
    log_info "========================================"

    cd "$PROJECT_ROOT"

    log_info "Building QCOW2 image using nixos-generators..."
    log_info "Configuration: hosts/nixos/k3s-template"
    log_info "Format: qcow2 (Proxmox compatible)"
    log_info "Output: $OUTPUT_DIR"
    log_info ""

    # Build the image
    log_info "Running nixos-generators (this may take 5-10 minutes)..."

    nix run github:nix-community/nixos-generators -- \
        --format qcow \
        --flake .#k3s-template \
        -o "$OUTPUT_DIR"

    # Find the generated image
    local image_file=$(ls -t "$OUTPUT_DIR"/nixos.qcow2 2>/dev/null | head -n 1)

    if [ -z "$image_file" ]; then
        log_error "Build failed - no image found in $OUTPUT_DIR/"
        exit 1
    fi

    log_info "✓ Image built: $image_file"

    # Calculate hash for change detection
    local image_hash=$(sha256sum "$image_file" | awk '{print $1}')

    log_info "✓ Image hash: $image_hash"

    # Write hash to file for Pulumi to check
    echo "$image_hash" > "$OUTPUT_DIR/image.sha256"

    log_info ""
    log_info "========================================"
    log_info "✓ Build Complete!"
    log_info "========================================"
    log_info "Image: $image_file"
    log_info "Hash: $image_hash"
}

main "$@"
