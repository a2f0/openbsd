#!/bin/sh
set -e

OPENBSD_VERSION="7.7"
OPENBSD_PERIOD_STRIPPED=$(echo "$OPENBSD_VERSION" | tr -d '.')
ISO_FILE="install$OPENBSD_PERIOD_STRIPPED.iso"

ARCH=$(uname -m)
if [ "$ARCH" != "x86_64" ]; then
    echo "Error: This script requires x86_64 architecture. Current architecture: $ARCH"
    exit 1
fi

# Check if required tools are available
check_dependencies() {
    local missing_deps=""
    
    for cmd in qemu-system-x86_64 qemu-img wget python3; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_deps="$missing_deps $cmd"
        fi
    done
    
    if [ -n "$missing_deps" ]; then
        echo "Error: Missing required dependencies:$missing_deps"
        echo "Please install QEMU, wget, and Python3:"
        echo "  Ubuntu/Debian: sudo apt install qemu-system-x86 wget python3"
        echo "  CentOS/RHEL: sudo yum install qemu-kvm wget python3"
        exit 1
    fi
}

# Check KVM availability and determine best acceleration method
check_kvm() {
    echo "Checking virtualization capabilities..."
    
    # Check if KVM module is loaded
    if lsmod | grep -q kvm; then
        echo "✓ KVM module is loaded"
    else
        echo "⚠ KVM module not loaded, trying to load it..."
        if sudo modprobe kvm 2>/dev/null; then
            echo "✓ KVM module loaded successfully"
        else
            echo "⚠ Could not load KVM module"
        fi
    fi
    
    # Check if user is in kvm group
    if groups | grep -q kvm; then
        echo "✓ User is in kvm group"
        KVM_AVAILABLE=true
    else
        echo "⚠ User is not in kvm group"
        echo "  You can add yourself to the kvm group with: sudo usermod -a -G kvm $USER"
        echo "  Then log out and back in, or run: newgrp kvm"
        KVM_AVAILABLE=false
    fi
    
    # Check if /dev/kvm exists and is accessible
    if [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
        echo "✓ /dev/kvm is accessible"
        KVM_DEVICE_AVAILABLE=true
    else
        echo "⚠ /dev/kvm is not accessible"
        KVM_DEVICE_AVAILABLE=false
    fi
}

# Get host IP for QEMU networking
get_host_ip() {
    HOST_IP=$(ip route get 1.1.1.1 | awk '{print $7; exit}')
    if [ -z "$HOST_IP" ]; then
        echo "Error: Could not determine host IP address"
        exit 1
    fi
    echo "Host IP: $HOST_IP"
}

# Start Python web server for autoinstall
start_web_server() {
    echo "Starting Python web server on port 8686..."
    python3 -m http.server 8686 &
    WEB_SERVER_PID=$!
    
    # Wait for web server to start listening
    echo "Waiting for web server to start listening on port 8686..."
    while ! netstat -tuln | grep -q ":8686 "; do
        sleep 0.1
    done
    echo "Web server is now listening on port 8686"
}

# Download OpenBSD ISO if it doesn't exist
download_iso() {
    if [ ! -f "$ISO_FILE" ]; then
        echo "Downloading OpenBSD $OPENBSD_VERSION ISO..."
        wget -O "$ISO_FILE" "https://cdn.openbsd.org/pub/OpenBSD/$OPENBSD_VERSION/amd64/$ISO_FILE"
        echo "Download completed: $ISO_FILE"
    else
        echo "ISO file already exists: $ISO_FILE"
    fi
}

# Create virtual disk if it doesn't exist
create_disk() {
    if [ ! -f "openbsd-vm.qcow2" ]; then
        echo "Creating virtual disk (2GB)..."
        qemu-img create -f qcow2 openbsd-vm.qcow2 2G
    else
        echo "Virtual disk already exists: openbsd-vm.qcow2"
    fi
}

# Extract kernel for autoinstall
extract_kernel() {
    echo "Extracting kernel from ISO..."
    if command -v isoinfo >/dev/null 2>&1; then
        isoinfo -i "$ISO_FILE" -R -x "/$OPENBSD_VERSION/amd64/bsd.rd" > bsd.rd
    else
        echo "Warning: isoinfo not found, skipping kernel extraction"
        echo "You may need to install genisoimage or cdrtools"
    fi
}

# Function to cleanup on exit
cleanup() {
    echo "Cleaning up..."
    if [ ! -z "$WEB_SERVER_PID" ]; then
        echo "Stopping Python web server (PID: $WEB_SERVER_PID)..."
        kill $WEB_SERVER_PID 2>/dev/null || true
    fi
    if [ ! -z "$QEMU_PID" ]; then
        echo "Stopping QEMU (PID: $QEMU_PID)..."
        kill $QEMU_PID 2>/dev/null || true
    fi
}

# Set trap to cleanup on script exit
trap cleanup EXIT

echo "=== OpenBSD $OPENBSD_VERSION QEMU Autoinstall Script ==="
echo

# Check dependencies
check_dependencies

# Check KVM availability
check_kvm

# Get host IP
get_host_ip

# Check if install.conf exists
if [ ! -f "install.conf" ]; then
    echo "Error: install.conf file not found!"
    echo "Please create an install.conf file or use qemu.sh for manual installation"
    exit 1
fi

# Download ISO and create disk
download_iso
create_disk

# Extract kernel for autoinstall
extract_kernel

# Start web server for autoinstall
start_web_server

echo
echo "Starting QEMU with OpenBSD $OPENBSD_VERSION autoinstall..."

# Determine best QEMU configuration based on KVM availability
if [ "$KVM_AVAILABLE" = true ] && [ "$KVM_DEVICE_AVAILABLE" = true ]; then
    echo "Using KVM acceleration for best performance..."
    QEMU_OPTS="-machine type=q35,accel=kvm -cpu host"
else
    echo "Using software emulation (slower but more compatible)..."
    QEMU_OPTS="-machine type=q35 -cpu qemu64"
fi

echo "Press Ctrl+A, then X to exit QEMU"
echo

# Start QEMU with autoinstall configuration
qemu-system-x86_64 \
    -m 2048 \
    -smp 2 \
    $QEMU_OPTS \
    -cdrom "$ISO_FILE" \
    -hda openbsd-vm.qcow2 \
    -boot d \
    -netdev user,id=mynet0 \
    -device e1000,netdev=mynet0 \
    -display gtk \
    -vga std \
    -usb \
    -device usb-tablet \
    -rtc base=utc \
    -serial mon:stdio \
    -kernel bsd.rd \
    -append "com0=/dev/ttyS0 console=com0 autoinstall=http://$HOST_IP:8686/install.conf" \
    -name "OpenBSD $OPENBSD_VERSION Autoinstall" &
QEMU_PID=$!

echo "QEMU started with PID: $QEMU_PID"
echo "Waiting for QEMU to exit..."
wait $QEMU_PID

echo "QEMU has exited." 
