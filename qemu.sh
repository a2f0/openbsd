#!/bin/sh
set -e

# Start Python web server in background
echo "Starting Python web server on port 8686..."
python3 -m http.server 8686 &
WEB_SERVER_PID=$!

# Function to cleanup on exit
cleanup() {
    echo "Cleaning up..."
    if [ ! -z "$WEB_SERVER_PID" ]; then
        echo "Stopping Python web server (PID: $WEB_SERVER_PID)..."
        kill $WEB_SERVER_PID 2>/dev/null || true
    fi
}

# Set trap to cleanup on script exit
trap cleanup EXIT

OPENBSD_VERSION="7.7"
ISO_FILE="install$OPENBSD_VERSION.iso"

ARCH=$(uname -m)
if [ "$ARCH" != "x86_64" ]; then
    echo "Error: This script requires x86_64 architecture. Current architecture: $ARCH"
    exit 1
fi

# Download OpenBSD ISO if it doesn't exist
if [ ! -f "$ISO_FILE" ]; then
    echo "Downloading OpenBSD $OPENBSD_VERSION ISO..."
    wget -O "$ISO_FILE" "https://cdn.openbsd.org/pub/OpenBSD/$OPENBSD_VERSION/amd64/$ISO_FILE"
    echo "Download completed: $ISO_FILE"
else
    echo "ISO file already exists: $ISO_FILE"
fi

# create and format the disk partition
qemu-img create -f qcow2 openbsd-vm.qcow2 2G

# The cleanup function will be called automatically when the script exits
echo "Script completed. Web server will be stopped automatically."


