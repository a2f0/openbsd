#!/bin/sh
set -e

# Get host IP for QEMU networking
HOST_IP=$(ip route get 1.1.1.1 | awk '{print $7; exit}')

# Start Python web server in background
echo "Starting Python web server on port 8686..."
python3 -m http.server 8686 &
WEB_SERVER_PID=$!

# Wait for web server to start listening
echo "Waiting for web server to start listening on port 8686..."
while ! netstat -tuln | grep -q ":8686 "; do
    sleep 0.1
done
echo "Web server is now listening on port 8686"

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
OPENBSD_PERIOD_STRIPPED=$(echo "$OPENBSD_VERSION" | tr -d '.')
ISO_FILE="install$OPENBSD_PERIOD_STRIPPED.iso"

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

isoinfo -i $ISO_FILE -R -x /$OPENBSD_VERSION/amd64/bsd.rd > bsd.rd

echo "Starting QEMU with network access to host IP: $HOST_IP"

export ISO_FILE
expect << 'EOF'
spawn qemu-system-x86_64 \
  -m 4096 \
  -nographic \
  -cdrom $env(ISO_FILE) \
  -hda openbsd-vm.qcow2 \
  -boot c

expect "boot>"
send "set tty com0\r"
expect "boot>"
send "boot\r"
expect -timeout 60 "(I)nstall, (U)pgrade, (A)utoinstall or (S)hell?"
send "A\r"
expect "Response file location?"
send "http://10.0.2.2:8686/install.conf\r"
expect -timeout 600 "login: "
interact
EOF

# The cleanup function will be called automatically when the script exits
echo "Script completed. Web server will be stopped automatically."
