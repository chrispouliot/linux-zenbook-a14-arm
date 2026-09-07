{ config, lib, pkgs, ... }:
{
  config = lib.mkIf config.hardware.asus.zenbookA14.diagnostics.ramoops32GiB.enable {
      # Temporary diagnostics for the supplied UX3407NA memory layout.
      # Required kernel options are set in kernel.nix, where buildLinux is called.
      hardware.deviceTree.overlays = [
        {
          name = "asus-a14-ramoops";
          filter = "glymur-asus-zenbook-a14-ux3407na.dtb";
          dtsText = ''
          /dts-v1/;
          /plugin/;
          
          / {
          	compatible = "asus,zenbook-a14-ux3407na", "qcom,glymur";
          
          	fragment@0 {
          		target-path = "/reserved-memory";
          		__overlay__ {
          			#address-cells = <2>;
          			#size-cells = <2>;
          
          			/*
          			 * UX3407NA, 32 GiB: checked against the supplied 2026-09-06
          			 * /proc/iomem and running DT. Reserve BEFORE Linux allocates
          			 * this memory; never point a live ramoops module at free RAM.
          			 * Range: 0xb80000000..0xb803fffff (4 MiB).
          			 * Firmware retention still requires a normal-reboot test.
          			 */
          			ramoops@b80000000 {
          				compatible = "ramoops";
          				reg = <0x0000000b 0x80000000 0x0 0x00400000>;
          				no-map;
          				mem-type = <0>;
          				record-size = <0x00080000>;
          				console-size = <0x00200000>;
          				pmsg-size = <0x00080000>;
          				max-reason = <2>;
          				ecc-size = <16>;
          			};
          		};
          	};
          };
          '';
        }
      ];

      boot.kernelParams = [
        "pstore.backend=ramoops"
        "efi_pstore.pstore_disable=1"
        "pm_debug_messages"
      ];

      # Keep recovered records available for direct inspection, including when
      # systemd-pstore has also archived them under /var/lib/systemd/pstore.
      environment.etc."systemd/pstore.conf.d/90-a14-ramoops.conf".text = ''
        [PStore]
        Storage=external
        Unlink=no
      '';

      environment.systemPackages = [
        (pkgs.writeShellApplication {
          name = "a14-ramoops";
          runtimeInputs = with pkgs; [
            coreutils findutils gnugrep gnutar gzip systemd
          ];
          text = ''
          # shellcheck shell=bash
          # Invoked by the NixOS-installed a14-ramoops command.
          set -euo pipefail
          
          if (( EUID != 0 )); then
            echo "Run with sudo: a14-ramoops status|mark|verify|collect" >&2
            exit 1
          fi
          
          state_dir=/var/lib/a14-ramoops
          backend_file=/sys/module/pstore/parameters/backend
          dt_node=/sys/firmware/devicetree/base/reserved-memory/ramoops@b80000000
          
          check_setup() {
            local backend
            backend=$(cat "$backend_file" 2>/dev/null || true)
            if [[ "$backend" != ramoops ]]; then
              echo "Expected ramoops; current pstore backend: $backend" >&2
              return 1
            fi
            if [[ ! -r "$dt_node/reg" || ! -e "$dt_node/no-map" ]]; then
              echo "The diagnostic reserved-memory node is missing or incomplete." >&2
              return 1
            fi
            if [[ "$(od -An -v -tx1 "$dt_node/reg" | tr -d ' \n')" != 0000000b800000000000000000400000 ]]; then
              echo "The running ramoops reservation does not match this diagnostic package." >&2
              return 1
            fi
            if [[ ! -c /dev/pmsg0 ]]; then
              echo "/dev/pmsg0 is missing; check CONFIG_PSTORE_PMSG and ramoops probe logs." >&2
              return 1
            fi
            if ! zcat /proc/config.gz | grep -x 'CONFIG_PSTORE_CONSOLE=y' >/dev/null; then
              echo "The running kernel lacks CONFIG_PSTORE_CONSOLE=y." >&2
              return 1
            fi
          }
          
          case "''${1:-status}" in
            status)
              check_setup
              echo "ramoops is registered; console and marker support are present."
              printf 'Reserved-memory reg bytes: '
              od -An -v -tx1 "$dt_node/reg"
              printf 'Console suspend: '
              cat /sys/module/printk/parameters/console_suspend
              printf 'Suspend diagnostics: '
              cat /sys/power/pm_debug_messages
              printf 'Memory sleep mode: '
              cat /sys/power/mem_sleep
              journalctl -b -k -o short-monotonic --no-pager |
                grep -E 'ramoops|persistent store backend|reserved mem.*[bB]80000000' || true
              ;;
            mark)
              check_setup
              install -d -m 0700 "$state_dir"
              boot_id=$(cat /proc/sys/kernel/random/boot_id)
              marker="A14_RAMOOPS_RETENTION_''${boot_id}_$(date +%s)"
              printf '%s\n' "$marker" > "$state_dir/expected-marker"
              printf '%s\n' "$boot_id" > "$state_dir/marker-boot-id"
              printf '%s\n' "$marker" > /dev/pmsg0
              printf '<6>%s\n' "$marker" > /dev/kmsg
              sync
              echo "Marker written: $marker"
              echo "Reboot normally, then run: sudo a14-ramoops verify"
              ;;
            verify)
              check_setup
              if [[ ! -r "$state_dir/expected-marker" || ! -r "$state_dir/marker-boot-id" ]]; then
                echo "No retention marker has been recorded. Run 'sudo a14-ramoops mark' first." >&2
                exit 1
              fi
              if [[ "$(cat "$state_dir/marker-boot-id")" == "$(cat /proc/sys/kernel/random/boot_id)" ]]; then
                echo "A normal reboot is required between mark and verify." >&2
                exit 1
              fi
              marker=$(cat "$state_dir/expected-marker")
              found_console=0
              found_pmsg=0
              for directory in /sys/fs/pstore /var/lib/systemd/pstore; do
                [[ -d "$directory" ]] || continue
                while IFS= read -r -d ''' record; do
                  if grep -aF "$marker" "$record" >/dev/null; then
                    printf 'Marker recovered from: %s\n' "$record"
                    case "$(basename "$record")" in
                      console-ramoops*) found_console=1 ;;
                      pmsg-ramoops*) found_pmsg=1 ;;
                    esac
                  fi
                done < <(find "$directory" -type f \( -name 'console-ramoops*' -o -name 'pmsg-ramoops*' \) -print0)
              done
              if (( found_console == 1 && found_pmsg == 1 )); then
                echo "PASS: both console and marker data survived a normal reboot."
                echo "This does not guarantee retention through every firmware reset."
              else
                echo "Retention check incomplete: console=$found_console pmsg=$found_pmsg" >&2
                echo "Run 'sudo a14-ramoops collect' and share the archive before another crash test." >&2
                exit 1
              fi
              ;;
            collect)
              # Keep collecting useful failure evidence even if the driver did not bind.
              out=$(mktemp -d /tmp/a14-ramoops-capture-XXXXXX)
              errors="$out/collection-errors.txt"
              for directory in /sys/fs/pstore /var/lib/systemd/pstore "$state_dir"; do
                if [[ -d "$directory" ]]; then
                  case "$directory" in
                    /sys/fs/pstore) destination=pstore-live ;;
                    /var/lib/systemd/pstore) destination=pstore-archived ;;
                    *) destination=retention-test ;;
                  esac
                  cp -a "$directory" "$out/$destination" 2>>"$errors" || true
                fi
              done
              cat "$backend_file" > "$out/backend.txt" 2>>"$errors" || true
              journalctl --list-boots --no-pager > "$out/boots.txt" 2>>"$errors" || true
              journalctl -b -1 -n 5000 -o short-monotonic --no-pager > "$out/previous-boot.log" 2>>"$errors" || true
              journalctl -b 0 -k -o short-monotonic --no-pager > "$out/current-kernel.log" 2>>"$errors" || true
              journalctl -b 0 -u systemd-pstore --no-pager > "$out/pstore-service.log" 2>>"$errors" || true
              {
                uname -a
                cat /proc/cmdline
                cat /sys/power/mem_sleep
                cat /sys/power/pm_debug_messages
                cat /sys/module/printk/parameters/console_suspend
                readlink -f /run/booted-system
                readlink -f /run/current-system
              } > "$out/system.txt" 2>>"$errors"
              cat /proc/iomem > "$out/iomem.txt" 2>>"$errors" || true
              zcat /proc/config.gz > "$out/kernel.config" 2>>"$errors" || true
              tar -czf "$out.tar.gz" -C "$out" .
              if [[ -n "''${SUDO_UID:-}" && -n "''${SUDO_GID:-}" ]]; then
                chown "$SUDO_UID:$SUDO_GID" "$out.tar.gz"
              fi
              printf '\nUpload: %s.tar.gz\n' "$out"
              ;;
            *)
              echo "Usage: sudo a14-ramoops status|mark|verify|collect" >&2
              exit 2
              ;;
          esac
          '';
        })
      ];
  };
}
