#!/usr/bin/env bash
set -euo pipefail

# Deploy NixOS image as Proxmox template
# This script takes a built image and deploys it to Proxmox

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

# Configuration from environment or defaults
TEMPLATE_ID="${TEMPLATE_ID:-9000}"
STORAGE="${STORAGE:-fast}"
IMAGE_DIR="${IMAGE_DIR:-$HOME/nixos-k3s-template}"

main() {
    log_info "========================================"
    log_info "Deploying NixOS Template to Proxmox"
    log_info "========================================"

    # Check if running on Proxmox
    if ! command -v qm &> /dev/null; then
        log_error "This script must be run on a Proxmox host (qm command not found)"
        exit 1
    fi

    # Find the image
    local image_file=$(ls -t "$IMAGE_DIR"/nixos.qcow2 2>/dev/null | head -n 1)

    if [ -z "$image_file" ]; then
        log_error "No image found in $IMAGE_DIR/"
        log_error "Run build-nixos-image.sh first"
        exit 1
    fi

    log_info "Image: $image_file"
    log_info "Template ID: $TEMPLATE_ID"
    log_info "Storage: $STORAGE"
    log_info ""

    # Remove existing template if it exists
    if qm status $TEMPLATE_ID &>/dev/null; then
        log_warn "VM $TEMPLATE_ID already exists. Removing..."
        qm destroy $TEMPLATE_ID || true
    fi

    # Create new VM
    log_info "Creating VM $TEMPLATE_ID..."
    qm create $TEMPLATE_ID \
        --name "k3s-template" \
        --memory 2048 \
        --cores 2 \
        --net0 virtio,bridge=vmbr0

    # Import the disk
    log_info "Importing disk..."
    qm importdisk $TEMPLATE_ID "$image_file" "$STORAGE"

    # Configure the VM to use the imported disk
    log_info "Configuring VM..."
    qm set $TEMPLATE_ID \
        --scsihw virtio-scsi-pci \
        --scsi0 "${STORAGE}:vm-${TEMPLATE_ID}-disk-0" \
        --boot order=scsi0 \
        --serial0 socket \
        --vga serial0 \
        --agent enabled=1

    # Convert to template
    log_info "Converting to template..."
    qm template $TEMPLATE_ID

    # Read and output the hash
    if [ -f "$IMAGE_DIR/image.sha256" ]; then
        local image_hash=$(cat "$IMAGE_DIR/image.sha256")
        log_info "Template hash: $image_hash"
        # Output hash for Pulumi to capture
        echo "$image_hash"
    fi

    log_info ""
    log_info "========================================"
    log_info "✓ Template Deployed Successfully!"
    log_info "========================================"
    log_info "Template ID: $TEMPLATE_ID"
    log_info "Storage: $STORAGE"
}

main "$@"
