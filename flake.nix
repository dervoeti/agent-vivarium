{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs, nixpkgs-unstable }:
    let
      lib = nixpkgs.lib;
      system = "x86_64-linux";
      unstable = import nixpkgs-unstable {
        inherit system;
        config.allowUnfree = true;
        overlays = [ (import ./pkgs/claude-code-overlay.nix) ];
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
                - |
                  kind: KubeletConfiguration
                  failSwapOn: false
                  featureGates:
                    NodeSwap: true
                  memorySwap:
                    swapBehavior: NoSwap
                nodes:
                - role: control-plane
              '';

              # Script to patch the node's reported capacity so the scheduler
              # thinks there is 64Gi of memory (RAM + swap backing).
              # Run once after "kind create cluster"; Ctrl-C to stop.
              kindPatchMemory = pkgs.writeShellScriptBin "kind-patch-memory" ''
                set -euo pipefail
                MEM="''${1:-64Gi}"
                NODE=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')
                echo "Patching node $NODE → $MEM (loop, Ctrl-C to stop)"

                # kubelet overwrites .status every ~10s so we keep patching
                kubectl proxy --port=8099 &
                PROXY=$!
                trap "kill $PROXY 2>/dev/null" EXIT

                while true; do
                  ${pkgs.curl}/bin/curl -s -X PATCH \
                    "http://localhost:8099/api/v1/nodes/$NODE/status" \
                    -H "Content-Type: application/strategic-merge-patch+json" \
                    -d "{\"status\":{\"capacity\":{\"memory\":\"$MEM\"},\"allocatable\":{\"memory\":\"$MEM\"}}}" \
                    > /dev/null
                  sleep 8
                done
              '';
              voiceInput = pkgs.writeShellScriptBin "voice-input" ''
              set -euo pipefail
              MODEL=''${WHISPER_MODEL:-/var/lib/whisper/ggml-base.en.bin}
              if [ ! -f "$MODEL" ]; then
                echo "Whisper model not found at $MODEL" >&2
                echo "Download it with:" >&2
                echo "  sudo mkdir -p /var/lib/whisper && sudo curl -fsSL https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin -o /var/lib/whisper/ggml-base.en.bin" >&2
                exit 1
              fi
              TMPFILE=$(mktemp /tmp/voice-XXXXXX.wav)
              trap 'rm -f "$TMPFILE" "''${TMPFILE%.wav}.txt"' EXIT
              printf "Recording... (speak now, silence stops recording)\n" >&2
              ${pkgs.sox}/bin/rec -q -r 16000 -c 1 -b 16 "$TMPFILE" \
                silence 1 0.1 3% 1 2.5 3% 2>/dev/null || true
              printf "Transcribing...\n" >&2
              ${pkgs.whisper-cpp}/bin/whisper-cli \
                -m "$MODEL" -f "$TMPFILE" \
                --output-txt --output-file "''${TMPFILE%.wav}" \
                2>/dev/null || true
              TXTFILE=''${TMPFILE%.wav}.txt
              if [ -f "$TXTFILE" ]; then
                sed 's/^\s*//;s/\s*$//' "$TXTFILE" | grep -v '^\[BLANK_AUDIO\]$' | tr -d '\n'
                printf "\n"
              fi
            '';

            speak = pkgs.writeShellScriptBin "speak" ''
              TEXT=''${*:-$(cat)}
              [ -z "$TEXT" ] && exit 0
              printf '%s\n' "$TEXT" | ${pkgs.espeak-ng}/bin/espeak-ng -v en -s 160
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
              unstable.opencode
              (pkgs.callPackage ./pkgs/ccometixline.nix {})
              (pkgs.callPackage ./pkgs/rtk.nix {})
              (pkgs.callPackage ./pkgs/antigravity.nix {})

              # Kubernetes
              (pkgs.callPackage ./pkgs/stackablectl.nix {})
              kindWrapped
              kindPatchMemory
              kubectl
              kustomize
              kubernetes-helm
              kuttl
              kubescape
              argocd
              tilt

              # Audio
              sox
              alsa-utils
              pulseaudio

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

              # Browsers
              chromium

              # Node
              nodejs_22

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
              nixfmt
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
            networking.firewall.allowedTCPPorts = [ 22 6443 3000 3001 3002 ];

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
              extraGroups = [ "docker" "audio" "pulse-access" ];
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
              EDITOR = "vim";
              COLORTERM = "truecolor";
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
              size = 32 * 1024; # 32 GB in MiB – backs Kubernetes swap scheduling
            }];

            nix.settings.experimental-features = [ "nix-command" "flakes" ];

            # Enable PulseAudio for voice input/output
            security.rtkit.enable = true;
            services.pulseaudio.enable = true;
            services.pulseaudio.systemWide = true;
            services.pulseaudio.extraConfig = ''
              set-source-mute alsa_input.pci-0000_00_0b.0.analog-stereo 0
              set-source-volume alsa_input.pci-0000_00_0b.0.analog-stereo 65536
            '';

            services.irqbalance.enable = true;

            # Periodically TRIM the fs so freed blocks are punched out of the
            # qcow2 backing file (needs discard=unmap on the drive, see vmVariant).
            services.fstrim.enable = true;

            boot.kernel.sysctl = {
              "net.ipv6.conf.all.disable_ipv6" = 1;
              "net.ipv6.conf.default.disable_ipv6" = 1;
              "vm.swappiness" = 60;
              "vm.max_map_count" = 262144;
              "fs.inotify.max_user_watches" = 524288;
              "fs.inotify.max_user_instances" = 1024;
              "kernel.pid_max" = 4194304;
              "net.core.somaxconn" = 32768;
              "net.ipv4.tcp_tw_reuse" = 1;
            };

            boot.postBootCommands = ''
              mount -o remount,cache=mmap /home/voeti/stackable 2>/dev/null || true
              mount -o remount,cache=mmap /home/voeti/projects 2>/dev/null || true
            '';

            system.stateVersion = "25.11";

            virtualisation.vmVariant = {
              virtualisation = {
                memorySize = 12288;
                cores = 16;
                diskSize = 327680; # 320GB
                writableStoreUseTmpfs = false;
                # Override the built-in root drive to enable discard so guest
                # TRIM/deletes shrink devVM.qcow2 instead of growing forever.
                # detect-zeroes=unmap also punches holes on zero writes.
                qemu.drives = lib.mkForce [{
                  name = "root";
                  file = ''"$NIX_DISK_IMAGE"'';
                  driveExtraOpts = {
                    cache = "writeback";
                    werror = "report";
                    discard = "unmap";
                    detect-zeroes = "unmap";
                  };
                  deviceExtraOpts = {
                    bootindex = "1";
                    serial = "root";
                  };
                }];
                qemu.networkingOptions = lib.mkForce [
                  "-netdev user,id=net0,hostfwd=tcp:127.0.0.1:2222-:22,hostfwd=tcp:127.0.0.1:45631-:45631,hostfwd=tcp:127.0.0.1:33000-:3000,hostfwd=tcp:127.0.0.1:33001-:3001,hostfwd=tcp:127.0.0.1:33002-:3002"
                  "-device virtio-net-pci,netdev=net0"
                ];
                sharedDirectories.projects = {
                  source = "/home/voeti/projects";
                  target = "/home/voeti/projects";
                  securityModel = "passthrough";
                };
                sharedDirectories.stackable = {
                  source = "/home/voeti/stackable";
                  target = "/home/voeti/stackable";
                  securityModel = "passthrough";
                };
                qemu.options = [
                  "-cpu host"
                  # Audio passthrough: use PulseAudio (works on PipeWire via compat layer too)
                  "-audiodev pa,id=audio0"
                  "-device intel-hda"
                  "-device hda-duplex,audiodev=audio0"
                ];
              };
            };
          })
        ];
      };
    };
}
