CLI to manage VMs called `vzm`.

Written in Swift and uses Apple's Virtualization (`Virtualization`) framework.

## Scope

V1 only supports:
- headless ARM Linux guests
- a bootable ASIF disk image as the source disk for `create`
- two commands: `create` and `run`

V1 does not include:
- `list`, `stop`, `delete`, or other lifecycle commands
- shared folders
- any virtual network interface
- the MITM HTTP(S) proxy implementation
- disk format conversion or import from non-ASIF formats

## Platform Requirements

`vzm` requires a macOS version whose Virtualization framework supports ASIF disk images.

The guest is assumed to be a preinstalled, bootable NixOS ARM image that already contains all required guest-side services and configuration.

## VM Model

All VMs are headless.

Do not attach any network interface to the VM.
Attach a virtio socket device and use vsock as the only host/guest transport.

Default VM hardware for V1:
- memory: 4 GiB
- vCPU: 2
- architecture: ARM guest only

## Host/Guest Transport Contract

Expose guest SSH port 22 to the host over vsock.

Use a fixed guest-side vsock port for SSH bridging:
- guest vsock port `2222` forwards to `127.0.0.1:22`

The host listens on the configured host SSH port and forwards accepted connections over vsock to guest port `2222`.

If the guest-side bridge is missing or not ready, `vzm run` should surface connection failures clearly, but V1 does not need an active readiness protocol beyond successful forwarding behavior.

## Proxy Model

Future versions may run a MITM HTTP(S) proxy on the host and expose it to the guest only over vsock.

Programs in the guest must use `HTTP_PROXY` and `HTTPS_PROXY` to access the network through that proxy.
Programs in the guest that do not use the proxy should have no network access.

The proxy is out of scope for V1 and must not block the initial implementation.

## Storage Layout

Store VM state under the user's Application Support directory:

`~/Library/Application Support/vzm/vms/<name>/`

Per-VM layout for V1:
- `config.json`
- `disk.asif`
- `runtime/lock`
- `runtime/pid`

`config.json` should include at least:
- schema version
- VM name
- cloned disk path
- configured host SSH port
- created timestamp

VM names must be restricted to lowercase letters, numbers, `-`, and `_`.

## Runtime Ownership

`run` must ensure only one host process owns a VM at a time.

Use a per-VM lock file plus persisted PID:
- on `run`, acquire the lock atomically
- if a lock already exists, inspect the recorded PID
- if the PID is alive and belongs to `vzm`, fail because the VM is already running
- if the PID is stale, recover the runtime state and continue

## Commands

### `vzm create <name> --disk <path> --ssh-port <port>`

Creates a new named VM from a preinstalled, bootable NixOS ASIF disk image.

Behavior:
- validate VM name
- validate that `<path>` exists and is an ASIF disk image
- validate that `--ssh-port` is a valid TCP port
- reject creation if another VM already uses the same configured SSH port
- create the VM directory under Application Support
- clone the specified ASIF disk into the VM directory as `disk.asif` using an APFS clone
- write `config.json`
- do not run the VM

`create` stores configuration only. It does not reserve the SSH port at the OS level.

### `vzm run <name>`

Runs a named VM in the foreground as an interactive host process.

The process is not a guest console or shell. It only displays current VM state and lifecycle events such as:
- VM name
- running state
- configured SSH port
- startup failure
- guest stop
- forced termination

Behavior:
- fail if the named VM does not exist
- fail if the VM is already running according to the runtime lock/PID check
- fail if the configured SSH host port is not currently bindable on the host
- start the VM and the host-side SSH forwarding bridge
- print state and block until VM exit or process interruption

On `CTRL-C` or process termination:
- attempt graceful shutdown by sending ACPI power to the guest
- wait up to 30 seconds for the guest to stop
- if the guest has not stopped, force terminate the host VM process

If forced termination is required, filesystem consistency inside the guest is not guaranteed.

VM startup failures and guest crashes should be reported to stderr.
