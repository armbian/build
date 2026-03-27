{
  description = "Flake for RaspberryPi support on NixOS";

  nixConfig = {
    extra-substituters = [
      "https://nixos-raspberrypi.cachix.org"
    ];
    extra-trusted-public-keys = [
      "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
    ];
    connect-timeout = 5;
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

    nixos-raspberrypi = {
      url = "github:nvmd/nixos-raspberrypi/main";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.argononed.follows = "argononed";
      inputs.flake-compat.follows = "flake-compat";
      inputs.nixos-images.follows = "nixos-images";
    };

    argononed = {
      # url = "git+file:../argononed?shallow=1";
      # url = "git+https://gitlab.com/DarkElvenAngel/argononed.git";
      url = "github:nvmd/argononed";
      flake = false;
    };

    nixos-images = {
      # url = "github:nix-community/nixos-images";
      url = "github:nvmd/nixos-images/sdimage-installer";
      # url = "git+file:../nixos-images?shallow=1";
      inputs.nixos-stable.follows = "nixpkgs";
      inputs.nixos-unstable.follows = "nixpkgs";
    };

    flake-compat.url = "github:edolstra/flake-compat";
    impermanence = {
      url = "github:nix-community/impermanence";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nixos-raspberrypi, argononed, nixos-images, ... }@inputs: let
    allSystems = nixpkgs.lib.systems.flakeExposed;
    forSystems = systems: f: nixpkgs.lib.genAttrs systems (system: f system);
  in {

    lib = nixos-raspberrypi.lib;

    nixosModules = nixos-raspberrypi.nixosModules // {


      immutable = { config, lib, pkgs, ... }: {
        fileSystems."/" = lib.mkForce {
          device = "none";
          fsType = "tmpfs";
          options = [ "defaults" "size=512M" "mode=755" ];
          neededForBoot = true;
        };
        fileSystems."/mnt-root" = {
          device = "/dev/disk/by-label/NIXOS_SD";
          fsType = "ext4";
          neededForBoot = true;
        };
        fileSystems."/nix" = lib.mkForce {
          device = "/mnt-root/nix";
          options = [ "bind" "noatime" ];
          neededForBoot = true;
        };
        fileSystems."/boot/firmware" = lib.mkDefault {
          device = "/dev/disk/by-label/FIRMWARE";
          fsType = "vfat";
          options = [ "nofail" "noatime" "x-systemd.automount" ];
          neededForBoot = true;
        };
        users.mutableUsers = false;
      };

      persistence = { config, lib, ... }: {
        imports = [ inputs.impermanence.nixosModules.impermanence ];
        environment.persistence."/mnt-root/persist" = {
          hideMounts = true;
          directories = [ "/var/log" "/var/lib/nixos" "/var/lib/systemd/coredump" ];
          files = [
            "/etc/machine-id"
            "/etc/ssh/ssh_host_ed25519_key"
            "/etc/ssh/ssh_host_ed25519_key.pub"
            "/etc/ssh/ssh_host_rsa_key"
            "/etc/ssh/ssh_host_rsa_key.pub"
          ];
        };
      };
    };

    overlays = nixos-raspberrypi.overlays;

    legacyPackages = nixos-raspberrypi.legacyPackages;

    packages = nixos-raspberrypi.packages;

    nixosConfigurations = let

      # TIP: To create "regular" nixosConfigurations look for
      # `nixosSystem` and `nixosSystemFull` helpers in `lib/`
      mkNixOSRPiInstaller = modules: nixos-raspberrypi.lib.nixosInstaller {
        specialArgs = inputs;
        modules = [
          nixos-images.nixosModules.sdimage-installer
          ({ config, lib, modulesPath, ... }: {
            disabledModules = [
              # disable the sd-image module that nixos-images uses
              (modulesPath + "/installer/sd-card/sd-image-aarch64-installer.nix")
            ];
            # nixos-images sets this with `mkForce`, thus `mkOverride 40`
            image.baseName = let
              cfg = config.boot.loader.raspberry-pi;
            in lib.mkOverride 40 "nixos-installer-rpi${cfg.variant}-${cfg.bootloader}";
          })
        ] ++ modules;
      };

      custom-user-config = ({ config, pkgs, lib, ... }: let
        requirementsTxt = builtins.readFile ./ip-terminal-code/requirements.txt;
        pythonPackageNames = let
          lines = lib.splitString "\n" requirementsTxt;
          validLines = lib.filter (line: line != "" && !lib.hasPrefix "#" line) lines;
          extractName = line: builtins.head (lib.splitString " " (builtins.head (lib.splitString "==" (builtins.head (lib.splitString ">=" line)))));
          normalizeName = name: lib.toLower (lib.replaceStrings ["."] ["-"] (lib.trim name));
        in lib.map (line: normalizeName (extractName line)) validLines;
      in {
        imports = [ ];

        system.stateVersion = "25.11";
        users.mutableUsers = false;

        # Set hostname
        networking.hostName = "IP-TERMINAL";

        # Enable NetworkManager
        networking.networkmanager = {
          enable = true;
          ensureProfiles.profiles.end0 = {
            connection = {
              id = "end0";
              type = "ethernet";
              interface-name = "end0";
            };
            ipv4.method = "auto";
            ipv6.method = "auto";
          };
        };

        # Set keyboard layout to Belgian
        i18n.defaultLocale = "en_US.UTF-8";
        console.keyMap = "be-latin1";

        services.openssh = {
          enable = true;
          settings = {
            PermitRootLogin = lib.mkForce "yes";
            PasswordAuthentication = true;
          };
        };

        users.users.cisco = {
          isNormalUser = true;
          extraGroups = [ "wheel" "spi" "gpio" "networkmanager" ];
          hashedPassword = "$6$Goen3jmm/N7uJcyV$wyOMkCxUNfM6sieOanFVYtT7ftIJmiPrBBcJOjHtJnskw57aWTbCPzTdV6c/uarg6ojOPLay7w4oG0Y/DrlrR1";
        };

        users.users.root = {
          hashedPassword = "$6$Goen3jmm/N7uJcyV$wyOMkCxUNfM6sieOanFVYtT7ftIJmiPrBBcJOjHtJnskw57aWTbCPzTdV6c/uarg6ojOPLay7w4oG0Y/DrlrR1";
        };

        security.sudo.extraRules = [{
          users = [ "cisco" ];
          commands = [
            { command = "/run/current-system/sw/bin/nmcli"; options = [ "NOPASSWD" ]; }
            { command = "/run/current-system/sw/bin/nmtui"; options = [ "NOPASSWD" ]; }
            { command = "/run/current-system/sw/bin/systemctl"; options = [ "NOPASSWD" ]; }
            { command = "/run/current-system/sw/bin/reboot"; options = [ "NOPASSWD" ]; }
            { command = "/run/current-system/sw/bin/shutdown"; options = [ "NOPASSWD" ]; }
          ];
        }];

        security.polkit.extraConfig = ''
          polkit.addRule(function(action, user) {
            if (action.id == "org.freedesktop.login1.reboot" ||
                action.id == "org.freedesktop.login1.reboot-multiple-sessions" ||
                action.id == "org.freedesktop.login1.power-off" ||
                action.id == "org.freedesktop.login1.power-off-multiple-sessions" ||
                action.id == "org.freedesktop.login1.halt" ||
                action.id == "org.freedesktop.login1.halt-multiple-sessions" ||
                action.id == "org.freedesktop.login1.suspend" ||
                action.id == "org.freedesktop.login1.suspend-multiple-sessions" ||
                action.id == "org.freedesktop.login1.hibernate" ||
                action.id == "org.freedesktop.login1.hibernate-multiple-sessions") {
              if (user.isInGroup("wheel")) {
                return polkit.Result.YES;
              }
            }
          });
        '';

        environment.systemPackages = with pkgs; [
          # Common tools
          tree
          htop
          btop
          fastfetch
          evtest
          dialog
          networkmanager

          # Networking tools
          dnsutils     # bind9-dnsutils
          traceroute   # traceroute
          netcat-gnu   # netcat-traditional
          inetutils    # telnet, etc.
          nmap         # nmap

          # Fonts
          dejavu_fonts

          # Custom config tool
          (writeShellScriptBin "config" ''
            export FONT_PATH="${pkgs.dejavu_fonts}/share/fonts/truetype/DejaVuSans.ttf"
            /opt/venv/bin/python /opt/ip-terminal-code/main.py --tui
          '')
        ];

        systemd.services.ip-terminal = {
          description = "IP Terminal Main Service";
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];
          path = with pkgs; [ networkmanager dialog ncurses ];
          serviceConfig = {
            Type = "simple";
            ExecStart = "/opt/venv/bin/python /opt/ip-terminal-code/main.py";
            WorkingDirectory = "/opt/ip-terminal-code";
            Environment = [
              "PYTHONUNBUFFERED=1"
              "FONT_PATH=${pkgs.dejavu_fonts}/share/fonts/truetype/DejaVuSans.ttf"
            ];
            Restart = "always";
            User = "root";
          };
          wantedBy = [ "multi-user.target" ];
        };

        systemd.tmpfiles.rules = [
          "L+ /opt/ip-terminal-code - - - - ${./ip-terminal-code}"
          "L+ /opt/venv - - - - ${pkgs.python3.withPackages (ps: lib.map (name: ps.${name}) pythonPackageNames)}"
        ];

        boot.kernelParams = [ "consoleblank=0" ];
        boot.kernelModules = [ "spidev" ];

        # Enable SPI overlay
        hardware.raspberry-pi.config.all.base-dt-params.spi = {
          enable = true;
          value = "on";
        };

        # Login welcome message
        environment.interactiveShellInit = ''
          # Only show for interactive logins
          case "$-" in
            *i*) ;;
            *) return ;;
          esac

          IFACE="end0"
          IP_ADDR=$(ip -4 addr show "$IFACE" 2>/dev/null | awk '/inet / {print $2}' | head -1)
          [ -z "$IP_ADDR" ] && IP_ADDR="(not configured)"
          GW=$(ip route show default 2>/dev/null | awk '/default/ {print $3}' | head -1)
          [ -z "$GW" ] && GW="(none)"
          DNS=$(resolvectl status 2>/dev/null | awk '/DNS Servers/ {print $3; exit}' | tr -d ' ')
          [ -z "$DNS" ] && DNS=$(awk '/^nameserver/ {print $2; exit}' /etc/resolv.conf 2>/dev/null)
          [ -z "$DNS" ] && DNS="(none)"

          printf '\n'
          printf '╔══════════════════════════════════════════╗\n'
          printf '║           IP Terminal – Welcome          ║\n'
          printf '╚══════════════════════════════════════════╝\n'
          printf '  IP        : %s\n' "$IP_ADDR"
          printf '  Gateway   : %s\n' "$GW"
          printf '  DNS       : %s\n' "$DNS"
          printf '\n'
          printf '  Type "config" to change IP address, prefix, gateway or DNS\n'
          printf '\n'
          printf '  Available tools:\n'
          printf '    ip neigh show  	display ARP table\n'
          printf '    ping         	send ICMP echo requests\n'
          printf '    traceroute   	trace packet route to host\n'
          printf '    nslookup     	query DNS records\n'
          printf '    dig          	DNS lookup utility\n'
          printf '    nc           	netcat – TCP/UDP connections\n'
          printf '    telnet       	telnet client\n'
          printf '\n'
        '';

        system.nixos.tags = let
          cfg = config.boot.loader.raspberry-pi;
        in [
          "raspberry-pi-${cfg.variant}"
          cfg.bootloader
          config.boot.kernelPackages.kernel.version
        ];
      });

    in {

      rpi02-installer = mkNixOSRPiInstaller [
        ({ config, pkgs, lib, nixos-raspberrypi, ... }: {
          imports = with nixos-raspberrypi.nixosModules; [
            # Hardware configuration
            raspberry-pi-02.base
            usb-gadget-ethernet
          ];
        })
        custom-user-config
      ];

      rpi3-installer = mkNixOSRPiInstaller [
        ({ config, pkgs, lib, nixos-raspberrypi, ... }: {
          imports = with nixos-raspberrypi.nixosModules; [
            # Hardware configuration
            raspberry-pi-3.base
          ];
        })
        custom-user-config
      ];

      rpi4-installer = mkNixOSRPiInstaller [
        ({ config, pkgs, lib, nixos-raspberrypi, ... }: {
          imports = with nixos-raspberrypi.nixosModules; [
            # Hardware configuration
            raspberry-pi-4.base
          ];
        })
        custom-user-config
      ];

      rpi5-installer = mkNixOSRPiInstaller [
        ({ config, pkgs, lib, nixos-raspberrypi, ... }: {
          imports = with nixos-raspberrypi.nixosModules; [
            # Hardware configuration
            raspberry-pi-5.base
            raspberry-pi-5.page-size-16k
          ];
        })
        custom-user-config
      ];

      rpi5 = nixos-raspberrypi.lib.nixosSystem {
        specialArgs = inputs;
        modules = [
          ({ config, pkgs, lib, nixos-raspberrypi, ... }: {
            imports = [
              nixos-raspberrypi.nixosModules.raspberry-pi-5.base
              nixos-raspberrypi.nixosModules.raspberry-pi-5.page-size-16k
              nixos-raspberrypi.nixosModules.raspberry-pi-5.display-vc4

              # Add the sd-image module to make it a bootable SD image
              nixos-raspberrypi.nixosModules.sd-image
            ];

          })
          custom-user-config
        ];
      };

      rpi5-immutable = nixos-raspberrypi.lib.nixosSystem {
        specialArgs = inputs;
        modules = [
          ({ config, pkgs, lib, nixos-raspberrypi, ... }: {
            imports = [
              nixos-raspberrypi.nixosModules.raspberry-pi-5.base
              nixos-raspberrypi.nixosModules.raspberry-pi-5.page-size-16k
              nixos-raspberrypi.nixosModules.raspberry-pi-5.display-vc4

              # Add the sd-image module to make it a bootable SD image
              nixos-raspberrypi.nixosModules.sd-image
              # Make it immutable/stateless
              self.nixosModules.immutable
              self.nixosModules.persistence
            ];

          })
          custom-user-config
        ];
      };

      rpi4 = nixos-raspberrypi.lib.nixosSystem {
        specialArgs = inputs;
        modules = [
          ({ config, pkgs, lib, nixos-raspberrypi, ... }: {
            imports = [
              nixos-raspberrypi.nixosModules.raspberry-pi-4.base
              nixos-raspberrypi.nixosModules.raspberry-pi-4.display-vc4

              # Add the sd-image module to make it a bootable SD image
              nixos-raspberrypi.nixosModules.sd-image
            ];

          })
          custom-user-config
        ];
      };

      rpi4-immutable = nixos-raspberrypi.lib.nixosSystem {
        specialArgs = inputs;
        modules = [
          ({ config, pkgs, lib, nixos-raspberrypi, ... }: {
            imports = [
              nixos-raspberrypi.nixosModules.raspberry-pi-4.base
              nixos-raspberrypi.nixosModules.raspberry-pi-4.display-vc4

              # Add the sd-image module to make it a bootable SD image
              nixos-raspberrypi.nixosModules.sd-image
              # Make it immutable/stateless
              self.nixosModules.immutable
              self.nixosModules.persistence
            ];

          })
          custom-user-config
        ];
      };

    };

    installerImages = let
      nixos = self.nixosConfigurations;
      mkImage = nixosConfig: nixosConfig.config.system.build.sdImage;
      mkUncompressed = nixosConfig: (nixosConfig.extendModules {
        modules = [ { sdImage.compressImage = false; } ];
      }).config.system.build.sdImage;
    in {
      rpi02 = mkImage nixos.rpi02-installer;
      rpi02-uncompressed = mkUncompressed nixos.rpi02-installer;
      rpi3 = mkImage nixos.rpi3-installer;
      rpi3-uncompressed = mkUncompressed nixos.rpi3-installer;
      rpi4 = mkImage nixos.rpi4-installer;
      rpi4-uncompressed = mkUncompressed nixos.rpi4-installer;
      rpi5 = mkImage nixos.rpi5-installer;
      rpi5-uncompressed = mkUncompressed nixos.rpi5-installer;
    };

    sdImages = let
      nixos = self.nixosConfigurations;
      mkImage = nixosConfig: nixosConfig.config.system.build.sdImage;
      mkUncompressed = nixosConfig: (nixosConfig.extendModules {
        modules = [ { sdImage.compressImage = false; } ];
      }).config.system.build.sdImage;
    in {
      rpi5 = mkImage nixos.rpi5;
      rpi5-uncompressed = mkUncompressed nixos.rpi5;
      rpi5-immutable = mkImage nixos.rpi5-immutable;
      rpi5-immutable-uncompressed = mkUncompressed nixos.rpi5-immutable;

      rpi4 = mkImage nixos.rpi4;
      rpi4-uncompressed = mkUncompressed nixos.rpi4;
      rpi4-immutable = mkImage nixos.rpi4-immutable;
      rpi4-immutable-uncompressed = mkUncompressed nixos.rpi4-immutable;
    };

  };
}
