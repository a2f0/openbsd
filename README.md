# OpenBSD

## Usage

### QEMU

1. Run `./qemu.exp` to provision the vm.
2. Run `./boot.exp` to use it (and `ssh -p 2222 a2f0@localhost` for ssh).

`./boot.exp --check` boots the vm without attaching to it, logs in on the console
with `USER_PASSWORD`, checks that sshd answers on port 2222, and powers the vm
off. CI runs it after the install.

