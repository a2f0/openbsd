# OpenBSD

## Usage

### QEMU

1. Run `./qemu.exp` to provision the vm.
2. Run `./boot.exp` to use it (and `ssh -p 2222 a2f0@localhost` for ssh).

`./qemu.exp` installs the ssh public key in `SSH_PUBLIC_KEY` for the user, or a
default key when it is unset.

`./boot.exp --check` boots the vm without attaching to it, logs in on the console
with `USER_PASSWORD`, logs in over ssh on port 2222 (with the private key in
`SSH_IDENTITY_FILE`, or ssh's defaults), and powers the vm off. CI runs it after
the install with a throwaway key pair.

