{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs, nixpkgs-unstable }:
    let
      lib = nixpkgs.lib;
      system = "x86_64-linux";
      unstable = import nixpkgs-unstable {
        inherit system;
        config.allowUnfree = true;
      };
      stackablectl = { stdenv, lib, pkgs, autoPatchelfHook }: stdenv.mkDerivation rec {
        pname = "stackablectl";
        version = "1.2.2";
        src = pkgs.fetchurl {
          url = "https://github.com/stackabletech/stackable-cockpit/releases/download/stackablectl-1.2.2/stackablectl-x86_64-unknown-linux-gnu";
          sha256 = "sha256-BZBFi7nYnzEuHfbtiGogZ2cXMfYwFsLq+vY0d/aggJw=";
        };
        dontUnpack = true;
        nativeBuildInputs = [ autoPatchelfHook ];
        buildInputs = [ stdenv.cc.cc ];
        sourceRoot = ".";
        installPhase = ''install -m755 -D $src $out/bin/stackablectl'';
        meta = with lib; {
          homepage = "https://stackable.tech";
          description = "Stackable CLI";
          platforms = platforms.linux;
        };
      };
    in {
      nixosConfigurations.devVM = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          ({ pkgs, ... }:
            let
              kindConfig = pkgs.writeText "kind-config.yaml" ''
                kind: Cluster
                apiVersion: kind.x-k8s.io/v1alpha4
                networking:
                  apiServerAddress: "0.0.0.0"
                  apiServerPort: 45631
                kubeadmConfigPatches:
                - |
                  kind: ClusterConfiguration
                  apiServer:
                    certSANs:
                    - "127.0.0.1"
                    - "0.0.0.0"
                    - "localhost"
                nodes:
                - role: control-plane
              '';
              kindWrapped = pkgs.writeShellScriptBin "kind" ''
                create_cluster=false
                has_config=false
                case "$*" in
                  *"create cluster"*) create_cluster=true ;;
                esac
                for arg in "$@"; do
                  case "$arg" in
                    --config|--config=*) has_config=true ;;
                  esac
                done

                if $create_cluster && ! $has_config; then
                  ${pkgs.kind}/bin/kind "$@" --config ${kindConfig}
                else
                  ${pkgs.kind}/bin/kind "$@"
                fi
                rc=$?

                if [ $rc -eq 0 ] && $create_cluster; then
                  sed -i 's|https://0.0.0.0:|https://127.0.0.1:|' "''${KUBECONFIG:-$HOME/.kube/config}"
                fi
                exit $rc
              '';
            in {
            nixpkgs.config.allowUnfree = true;

            services.getty.autologinUser = "voeti";

            environment.systemPackages = with pkgs; [
              # AI tools
              unstable.claude-code

              # Kubernetes
              (pkgs.callPackage stackablectl {})
              kindWrapped
              kubectl
              kustomize
              kubernetes-helm
              kuttl
              kubescape
              argocd

              # Containers & registries
              docker-compose
              crane
              oras
              cosign

              # Infrastructure
              opentofu
              ansible

              # Security & scanning
              trivy
              grype
              syft

              # Secrets & certificates
              step-cli
              step-ca
              gnupg

              # Rust
              rustc
              cargo
              rustfmt
              clippy
              rust-analyzer
              cargo-watch

              # Go
              go
              delve

              # Python
              python3
              poetry
              ruff
              uv
              pre-commit

              # Node
              nodejs_20

              # Java
              jdk21
              maven

              # C/C++ build tools
              gcc
              gnumake
              pkg-config
              cmake

              # Linters & formatters
              shellcheck
              actionlint
              tflint
              hadolint
              yamllint
              nixfmt-rfc-style
              nixpkgs-fmt

              # CLI utilities
              git
              jq
              fx
              ripgrep
              fd
              tmux
              htop
              just
              direnv
              nix-index
              tree
              unzip
              zip
              bc
              lnav
              dust
              gettext  # provides envsubst
              openssl
              openssl.dev
              libxml2
              vim
              nmap
              gh
              yq-go
            ];

            networking.hostName = "devVM";
            networking.firewall.allowedTCPPorts = [ 22 6443 3000 ];

            # Allow internet but block host OS and local network.
            # SLIRP DNS is at 10.0.2.3, so exempt it before blocking 10.0.0.0/8.
            networking.firewall.extraCommands = ''
              # Allow responses for already-established connections (e.g. inbound SSH via port-forward)
              iptables -I OUTPUT 1 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
              # Allow DNS to SLIRP's internal resolver
              iptables -I OUTPUT 2 -d 10.0.2.3 -p udp --dport 53 -j ACCEPT
              iptables -I OUTPUT 3 -d 10.0.2.3 -p tcp --dport 53 -j ACCEPT
              # Allow Docker/kind networks (pinned to 172.20.0.0/14 via daemon.json)
              iptables -I OUTPUT 4 -d 172.20.0.0/14 -j ACCEPT
              # Block host OS and local network ranges
              iptables -A OUTPUT -d 10.0.0.0/8 -j DROP
              iptables -A OUTPUT -d 172.16.0.0/12 -j DROP
              iptables -A OUTPUT -d 192.168.0.0/16 -j DROP
              iptables -A OUTPUT -d 169.254.0.0/16 -j DROP
            '';
            networking.firewall.extraStopCommands = ''
              iptables -D OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true
              iptables -D OUTPUT -d 10.0.2.3 -p udp --dport 53 -j ACCEPT 2>/dev/null || true
              iptables -D OUTPUT -d 10.0.2.3 -p tcp --dport 53 -j ACCEPT 2>/dev/null || true
              iptables -D OUTPUT -d 172.20.0.0/14 -j ACCEPT 2>/dev/null || true
              iptables -D OUTPUT -d 10.0.0.0/8 -j DROP 2>/dev/null || true
              iptables -D OUTPUT -d 172.16.0.0/12 -j DROP 2>/dev/null || true
              iptables -D OUTPUT -d 192.168.0.0/16 -j DROP 2>/dev/null || true
              iptables -D OUTPUT -d 169.254.0.0/16 -j DROP 2>/dev/null || true
            '';

            services.openssh = {
              enable = true;
              settings.PasswordAuthentication = false;
            };

            users.users.voeti = {
              isNormalUser = true;
              uid = 1000;
              extraGroups = [ "docker" ];
              openssh.authorizedKeys.keys = [
                "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJyKfjroqIznF6O5R7OessqLHWlNy7PDF+PblxQeiAsa"
              ];
            };

            users.users.root.openssh.authorizedKeys.keys = [
              "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJyKfjroqIznF6O5R7OessqLHWlNy7PDF+PblxQeiAsa"
            ];

            # Symlink ~/.kube/config into the shared directory so the host can use it directly.
            system.activationScripts.kubeconfig-symlink = ''
              mkdir -p /home/voeti/stackable/.kube
              mkdir -p /home/voeti/.kube
              chown voeti:users /home/voeti/stackable/.kube /home/voeti/.kube
              ln -sfn /home/voeti/stackable/.kube/config /home/voeti/.kube/config
            '';

            environment.sessionVariables = {
              PKG_CONFIG_PATH = "${pkgs.openssl.dev}/lib/pkgconfig";
            };

            environment.shellAliases = {
              ga = "git add";
              gs = "git status";
              gd = "git diff";
              gcm = "git commit -m";
              gp = "git push";
              gpl = "git pull";
              k = "kubectl";
              kgp = "kubectl get pods";
              kgn = "kubectl get nodes";
              kgpw = "kubectl get pods -o wide";
              kgnw = "kubectl get nodes -o wide";
              dod = "docker-compose down";
              dud = "docker-compose up -d";
            };

            programs.bash.completion.enable = true;
            programs.bash.interactiveShellInit = ''
              source <(kubectl completion bash)
              complete -F __start_kubectl k
            '';

            programs.zoxide.enable = true;
            programs.direnv.enable = true;
            programs.direnv.nix-direnv.enable = true;

            virtualisation.docker.enable = true;
            virtualisation.docker.daemon.settings = {
              # Pin all Docker networks to 172.20.0.0/14 so the firewall rule is predictable.
              # 172.20.0.0/16 → docker0 (default bridge)
              # 172.21–23.0.0/16 → user-defined networks (kind, etc.)
              bip = "172.20.0.1/16";
              default-address-pools = [
                { base = "172.20.0.0/14"; size = 16; }
              ];
            };
            swapDevices = [{
              device = "/var/lib/swapfile";
              size = 32 * 1024; # 32 GB in MiB
            }];

            nix.settings.experimental-features = [ "nix-command" "flakes" ];

            services.irqbalance.enable = true;

            boot.kernel.sysctl = {
              "net.ipv6.conf.all.disable_ipv6" = 1;
              "net.ipv6.conf.default.disable_ipv6" = 1;
              "vm.swappiness" = 1;
              "vm.max_map_count" = 262144;
              "fs.inotify.max_user_watches" = 524288;
              "fs.inotify.max_user_instances" = 1024;
              "kernel.pid_max" = 4194304;
              "net.core.somaxconn" = 32768;
              "net.ipv4.tcp_tw_reuse" = 1;
            };

            boot.postBootCommands = ''
              mount -o remount,cache=mmap /home/voeti/stackable 2>/dev/null || true
            '';

            system.stateVersion = "25.11";

            virtualisation.vmVariant = {
              virtualisation = {
                memorySize = 16384;
                cores = 16;
                diskSize = 327680; # 320GB
                qemu.networkingOptions = lib.mkForce [
                  "-netdev user,id=net0,hostfwd=tcp:127.0.0.1:2222-:22,hostfwd=tcp:127.0.0.1:45631-:45631,hostfwd=tcp:127.0.0.1:33000-:3000"
                  "-device virtio-net-pci,netdev=net0"
                ];
                sharedDirectories.stackable = {
                  source = "/home/voeti/stackable";
                  target = "/home/voeti/stackable";
                };
                qemu.options = [ "-cpu host" ];
              };
            };
          })
        ];
      };
    };
}
