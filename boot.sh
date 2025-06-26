#!/bin/sh

qemu-system-x86_64 \
    -m 4096 \
    -smp cpus=2 \
    -nographic \
    -serial mon:stdio \
    -hda openbsd-vm.qcow2 \
    -boot c
