inputs: hardwarePkgs:
{ config, lib, pkgs, ... }:
let
  cfg = config.hardware.asus.zenbookA14;
  a14AudioTopology = hardwarePkgs.runCommand "a14-audio-topology-hdmi" {
    nativeBuildInputs = [
      hardwarePkgs.buildPackages.alsa-utils
      hardwarePkgs.buildPackages.gnum4
    ];
  } ''
    cp -a ${inputs.audioreach-topology} source
    chmod -R u+w source

    install -m644 \
      ${../patches/a14-hdmi-topology.m4} \
      source/GLYMUR-CRD.m4

    (
      cd source

      m4 -I . GLYMUR-CRD.m4 \
        > GLYMUR-ASUS-Zenbook-A14-UX3407NA.conf

      alsatplg \
        -c GLYMUR-ASUS-Zenbook-A14-UX3407NA.conf \
        -o GLYMUR-ASUS-Zenbook-A14-UX3407NA-tplg.bin
    )

    install -Dm644 \
      source/GLYMUR-ASUS-Zenbook-A14-UX3407NA-tplg.bin \
      $out/lib/firmware/qcom/glymur/GLYMUR-ASUS-Zenbook-A14-UX3407NA-tplg.bin
  '';


  # ------------------------------------------------------------
  # ASUS UX3407NA two-speaker UCM
  # ------------------------------------------------------------

  # Keep the always-available internal Speaker and Mic devices in UCM.
  #
  # Do NOT put HDMI in this HiFi verb. Qualcomm DP audio PCM hw:0,4
  # legitimately returns -EINVAL while no display is connected. ACP probes
  # every PCM in a UCM profile, so including HDMI here causes WirePlumber to
  # reject the entire HiFi profile whenever HDMI is unplugged, taking the
  # internal speakers and microphones down with it.
  #
  # HDMI is exposed separately at runtime by a14HdmiAudioHotplug below.
  # alsa-ucm-conf PR #858 at c9d323590229951391433ed88ae2061df897ff2b.
  # The direct card mapping preserves the working DMI alias on our kernel.
  a14Ucm = hardwarePkgs.runCommand "a14-ucm-two-speaker" {} ''
    mkdir -p $out/share/alsa
    cp -a ${hardwarePkgs.alsa-ucm-conf}/share/alsa/ucm2 $out/share/alsa/ucm2
    chmod -R u+w $out/share/alsa/ucm2
    cp -r ${../patches/audio/ucm2}/. $out/share/alsa/ucm2/

    ln -sf ../../Qualcomm/glymur/ASUS-Zenbook-A14-UX3407NA.conf \
      $out/share/alsa/ucm2/conf.d/glymur/ASUSTeKCOMPUTERINC.-ZenbookA14UX3407NA-1.0-UX3407NA.conf

    grep -q 'PlaybackChannels 2' \
      $out/share/alsa/ucm2/Qualcomm/glymur/ZenbookA14-HiFi.conf
    if grep -qE 'HDMI2|DISPLAY_PORT_RX_2|DP2 Jack|CardId},4|Wsa2Speaker' \
      $out/share/alsa/ucm2/Qualcomm/glymur/ZenbookA14-HiFi.conf
    then
      echo "ERROR: unexpected HDMI or WSA2 route in the A14 internal UCM profile"
      exit 1
    fi
  '';


  # ------------------------------------------------------------
  # ASUS UX3407NA HDMI hotplug bridge
  # ------------------------------------------------------------

  # The kernel/topology exposes HDMI as MultiMedia5 (hw:0,4), with
  # connection state reported by the read-only "DP2 Jack" ALSA control.
  # hw:0,4 cannot be prepared while HDMI is disconnected, so keep it out of
  # ACP/UCM probing and instantiate it only while the jack is actually on.
  #
  # PipeWire 1.6's PulseAudio compatibility layer provides a built-in
  # module-alsa-sink. The helper below loads that module on HDMI connect and
  # unloads it on disconnect. It retries once per second while the jack is on,
  # which also covers the small interval where the display link is detected
  # before its audio engine is ready.
  a14HdmiAudioHotplug = pkgs.writeShellApplication {
    name = "a14-hdmi-audio-hotplug";

    runtimeInputs = [
      pkgs.alsa-utils
      pkgs.pulseaudio
      pkgs.coreutils
      pkgs.gawk
      pkgs.gnused
    ];

    text = ''
      sink_name="a14_hdmi"

      module_ids() {
        pactl list modules short 2>/dev/null | \
          awk -v sink="$sink_name" '
            $2 == "module-alsa-sink" && index($0, "sink_name=" sink) {
              print $1
            }
          ' || true
      }

      sink_loaded() {
        pactl list sinks short 2>/dev/null | \
          awk -v sink="$sink_name" '
            $2 == sink { found = 1 }
            END { exit !found }
          '
      }

      set_hdmi_mixer() {
        value="$1"
        amixer -c 0 cset \
          name='DISPLAY_PORT_RX_2 Audio Mixer MultiMedia5' \
          "$value" >/dev/null 2>&1 || true
      }

      unload_hdmi() {
        while IFS= read -r module_id; do
          if [ -n "$module_id" ]; then
            pactl unload-module "$module_id" >/dev/null 2>&1 || true
          fi
        done < <(module_ids)

        set_hdmi_mixer 0,0
      }

      load_hdmi() {
        if sink_loaded; then
          return 0
        fi

        # The AudioReach backend has a two-value mixer switch. Both channels
        # must be on; a scalar "1" only enabled the first one in testing.
        set_hdmi_mixer 1,1

        if pactl load-module module-alsa-sink \
          sink_name="$sink_name" \
          device=hw:0,4 \
          format=s16le \
          rate=48000 \
          channels=2 \
          channel_map=front-left,front-right \
          sink_properties=device.description=HDMI \
          >/dev/null 2>&1
        then
          return 0
        fi

        set_hdmi_mixer 0,0
        return 1
      }

      jack_state() {
        amixer -c 0 cget iface=CARD,name='DP2 Jack' 2>/dev/null | \
          sed -n 's/.*: values=\(on\|off\).*/\1/p' | \
          tail -n 1 || true
      }

      cleanup() {
        unload_hdmi
      }

      trap cleanup EXIT INT TERM

      # pipewire-pulse may be socket activated. Wait until pactl can talk to
      # it before inspecting or creating modules.
      until pactl info >/dev/null 2>&1; do
        sleep 1
      done

      # Remove any stale instance left by a prior helper/PipeWire restart.
      unload_hdmi

      last_state=""

      while true; do
        state="$(jack_state)"

        if [ "$state" = "on" ]; then
          # Keep retrying while connected in case the DP link/audio engine
          # needs another moment after the jack notification.
          load_hdmi || true
        else
          if [ "$last_state" = "on" ] || sink_loaded; then
            unload_hdmi
          fi
        fi

        last_state="$state"
        sleep 1
      done
    '';
  };


in {
  config = lib.mkIf cfg.audio.enable {
    hardware.firmware = lib.mkBefore [ a14AudioTopology ];
    security.rtkit.enable = lib.mkDefault true;
    services.pipewire = {
      enable = lib.mkDefault true;
      alsa.enable = lib.mkDefault true;
      pulse.enable = lib.mkDefault true;
      wireplumber.enable = lib.mkDefault true;
    };
  # Use the corrected always-on Speaker + Mic UCM tree for programs launched
  # from the desktop/session as well as diagnostic ALSA utilities.
  environment.sessionVariables.ALSA_CONFIG_UCM2 =
    "${a14Ucm}/share/alsa/ucm2";

  # WirePlumber owns ALSA device/profile discovery, so this service also needs
  # the custom UCM path explicitly.
  systemd.user.services.wireplumber.environment.ALSA_CONFIG_UCM2 =
    "${a14Ucm}/share/alsa/ucm2";



  # ------------------------------------------------------------
  # ASUS UX3407NA stereo speaker mapping + configurable gain
  # ------------------------------------------------------------

  # The topology and UCM now expose two channels matching SpkrLeft/SpkrRight.
  # Keep the user's speakerGain inside the existing single visible speaker node.
  #
  # Force the A14 card to the UCM HiFi profile. HDMI is no longer part of that
  # profile, so HiFi remains valid whether a display is connected or not.
  environment.etc."wireplumber/wireplumber.conf.d/90-a14-speakers.conf".text = ''
    monitor.alsa.rules = [
      {
        matches = [
          {
            device.name = "alsa_card.platform-sound"
          }
        ]

        actions = {
          update-props = {
            api.alsa.use-acp = true
            api.alsa.use-ucm = true
            device.profile = "HiFi"
          }
        }
      }
      {
        matches = [
          {
            node.name = "alsa_output.platform-sound.HiFi__Speaker__sink"
          }
        ]

        actions = {
          update-props = {
            audio.channels = 2
            audio.position = [ FL FR ]
            node.description = "Speakers"
            priority.session = 1400
          }
        }
      }
    ]

    node.filter-graph.rules = [
      {
        matches = [
          {
            node.name = "alsa_output.platform-sound.HiFi__Speaker__sink"
          }
        ]

        actions = {
          create-filter-graph = [
            {
              nodes = [
                {
                  type = builtin
                  name = gain
                  label = linear

                  control = {
                    Mult = ${toString cfg.audio.speakerGain}
                    Add = 0.0
                  }
                }
              ]
            }
          ]
        }
      }
    ]
  '';


  # ------------------------------------------------------------
  # ASUS UX3407NA HDMI audio hotplug
  # ------------------------------------------------------------

  # Expose a conventional two-channel PipeWire sink named "HDMI" only while
  # DP2 Jack is connected. Keeping hw:0,4 out of UCM avoids ACP rejecting the
  # entire HiFi profile when no TV/receiver is present.
  systemd.user.services.a14-hdmi-audio-hotplug = {
    description = "ASUS A14 HDMI audio hotplug";

    wantedBy = [ "default.target" ];
    wants = [
      "pipewire-pulse.service"
      "wireplumber.service"
    ];
    after = [
      "pipewire-pulse.service"
      "wireplumber.service"
    ];

    serviceConfig = {
      Type = "simple";
      ExecStart = "${a14HdmiAudioHotplug}/bin/a14-hdmi-audio-hotplug";
      Restart = "always";
      RestartSec = 1;
    };
  };


  };
}
