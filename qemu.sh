#!/bin/sh
set -e

qemu-img create -f qcow2 openbsd-vm.qcow2 2G
