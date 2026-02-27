# agent-vivarium

A NixOS VM for sandboxing AI coding agents (like Claude Code). The agent gets a full dev environment with Docker, Kind, and Kubernetes tooling while being network-isolated from the host and local network.

This is my personal project to experiment with safe agent sandboxing. It's not intended for production use or as a general-purpose agent environment. Use at your own risk, and see the "Known trade-offs" section below. I published it mainly to share my learnings, and maybe someone will find some things useful for their own projects.

## Why a VM?

Allowlisting shell commands in agent config files is fragile. Tools like `find -exec` can run arbitrary commands, and Docker-in-Docker or Kind introduce their own escape vectors. A VM provides a hard boundary that's easy to reason about: the agent can do whatever it wants inside without any realistic path to the host.

## What's inside

All the tools I currently use for daily development and testing.

## Network isolation

The VM uses iptables rules to block all outbound traffic to the host and local network:

```
10.0.0.0/8       -> DROP
172.16.0.0/12    -> DROP
192.168.0.0/16   -> DROP
169.254.0.0/16   -> DROP
```

With explicit exemptions for:

- **SLIRP DNS** (10.0.2.3), so the VM can resolve hostnames
- **Docker/Kind subnets** (172.20.0.0/14), pinned via `daemon.json` so the rules are stable

The public internet is reachable. Only LAN traffic is blocked.

## Prerequisites

- NixOS or a system with Nix installed (with flakes enabled)
- KVM support (`/dev/kvm`)

## Usage

Build and run the VM:

```bash
./run-vm.sh
```

This runs `nixos-rebuild build-vm --flake .#devVM` and launches the resulting QEMU VM.

### SSH access

The VM forwards port 2222 to its SSH server:

```bash
ssh -p 2222 voeti@localhost
```

### Port forwards

| Host port | VM port | Purpose |
|-----------|---------|---------|
| 2222 | 22 | SSH |
| 45631 | 45631 | Kind API server |
| 33000 | 3000 | General (e.g. Grafana) |

### Shared directory

The host's `/home/voeti/stackable` is mounted into the VM at the same path via virtfs. The VM symlinks `~/.kube/config` into this directory so you can use `kubectl` from the host against the Kind cluster running inside the VM.

## VM resources

| Resource | Default |
|----------|---------|
| Memory | 16 GB |
| CPU cores | 16 |
| Disk | 320 GB |
| Swap | 32 GB |

These can be adjusted in the `virtualisation.vmVariant` section of `flake.nix`.

## Known trade-offs

- Shared directory is bidirectional: the agent can write files the host will see. Don't blindly execute anything from the shared directory without reviewing it first.
- Outbound internet is unrestricted: the agent can reach the public internet, which means it could exfiltrate data from the shared directory. If that contains sensitive code, consider restricting outbound via a proxy.

## License

MIT
