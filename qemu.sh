#!/bin/sh
set -e

OPENBSD_VERSION="7.7"
ISO_FILE="install77.iso"

ARCH=$(uname -m)
if [ "$ARCH" != "x86_64" ]; then
    echo "Error: This script requires x86_64 architecture. Current architecture: $ARCH"
    exit 1
fi

# Download OpenBSD ISO if it doesn't exist
ISO_FILE="install$OPENBSD_VERSION.iso"
if [ ! -f "$ISO_FILE" ]; then
    echo "Downloading OpenBSD $OPENBSD_VERSION ISO..."
    wget -O "$ISO_FILE" "https://cdn.openbsd.org/pub/OpenBSD/7.7/amd64/install77.iso"
    echo "Download completed: $ISO_FILE"
else
    echo "ISO file already exists: $ISO_FILE"
fi

# create and format the disk partition
qemu-img create -f qcow2 openbsd-vm.qcow2 2G


