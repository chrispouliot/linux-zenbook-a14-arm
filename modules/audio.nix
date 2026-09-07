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
  a14Ucm = hardwarePkgs.runCommand "a14-ucm-two-speaker" {
    nativeBuildInputs = [
      hardwarePkgs.buildPackages.gnused
    ];
  } ''
    mkdir -p $out/share/alsa

    cp -a \
      ${hardwarePkgs.alsa-ucm-conf}/share/alsa/ucm2 \
      $out/share/alsa/ucm2

    chmod -R u+w $out/share/alsa/ucm2


    # ------------------------------------------------------------
    # ASUS UX3407NA card-name mapping
    # ------------------------------------------------------------

    ln -sf \
      ../../Qualcomm/glymur/GLYMUR-CRD.conf \
      $out/share/alsa/ucm2/conf.d/glymur/ASUSTeKCOMPUTERINC.-ZenbookA14UX3407NA-1.0-UX3407NA.conf


    # ------------------------------------------------------------
    # Keep only the two physical WSA8845 codecs on swr0
    # ------------------------------------------------------------

    # The current DT names the two real swr0 codecs WooferLeft and
    # TweeterLeft, despite them functioning as the laptop's two physical
    # stereo speakers.
    #
    # Remove only the nonexistent codecs currently described as
    # WooferRight/TweeterRight on swr3.
    for f in \
      $out/share/alsa/ucm2/codecs/wsa884x/four-speakers/SpeakerSeq.conf \
      $out/share/alsa/ucm2/codecs/wsa884x/four-speakers/DefaultEnableSeq.conf \
      $out/share/alsa/ucm2/codecs/wsa884x/four-speakers/init.conf
    do
      sed -i \
        -e '/WooferRight/d' \
        -e '/TweeterRight/d' \
        "$f"
    done


    # ------------------------------------------------------------
    # Remove WSA2/swr3 from the Glymur UCM
    # ------------------------------------------------------------

    # Only WSA/swr0 is physically populated on the UX3407NA.
    sed -i \
      -e '/Wsa2SpeakerEnableSeq/d' \
      -e '/Wsa2SpeakerDisableSeq/d' \
      $out/share/alsa/ucm2/Qualcomm/glymur/HiFi.conf

    # The generic four-speaker card initialization also configures the
    # WSA2 macro. Remove those commands for this machine.
    sed -i \
      '/WSA2/d' \
      $out/share/alsa/ucm2/codecs/qcom-lpass/wsa-macro/four-speakers/init.conf


    # ------------------------------------------------------------
    # Sanity checks
    # ------------------------------------------------------------

    # MultiMedia1 remains the stock four-channel AudioReach frontend.
    grep -q \
      'PlaybackChannels 4' \
      $out/share/alsa/ucm2/Qualcomm/glymur/HiFi.conf

    # HDMI must not be part of the always-on UCM HiFi profile.
    if grep -qE \
      'HDMI2|DISPLAY_PORT_RX_2|DP2 Jack|CardId},4' \
      $out/share/alsa/ucm2/Qualcomm/glymur/HiFi.conf
    then
      echo "ERROR: HDMI leaked into the always-on A14 UCM HiFi profile"
      exit 1
    fi

    if grep -RqiE \
      'WooferRight|TweeterRight|Wsa2Speaker' \
      $out/share/alsa/ucm2/Qualcomm/glymur \
      $out/share/alsa/ucm2/codecs/wsa884x/four-speakers
    then
      echo "ERROR: nonexistent WSA2 speaker references remain in A14 UCM"
      exit 1
    fi

    echo "ASUS A14 always-on Speaker + Mic UCM prepared successfully"
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
  # ASUS UX3407NA speaker mapping + transparent 1.50x boost
  # ------------------------------------------------------------

  # MultiMedia1 is intentionally a four-channel frontend, while the two real
  # physical speakers occupy slots 0 and 2:
  #
  #   slot 0 -> physical left
  #   slot 1 -> unused
  #   slot 2 -> physical right
  #   slot 3 -> unused
  #
  # Tell PipeWire that layout so ordinary stereo FL/FR lands on slots 0/2.
  # Apply the 1.50x gain *inside* the real speaker node with WirePlumber's
  # internal filter graph. This gives desktop applications exactly one visible
  # internal output named "Speakers"; there is no separate raw/boosted sink.
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
            audio.channels = 4
            audio.position = [ FL RL FR RR ]
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
