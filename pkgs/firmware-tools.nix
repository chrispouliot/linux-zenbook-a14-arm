{ python3, runCommand }:
runCommand "a14-firmware-tools" { } ''
  mkdir -p $out/bin $out/share/a14-firmware
  cp ${../scripts/firmware.py} $out/share/a14-firmware/firmware.py
  cp ${../firmware-manifest.json} $out/share/a14-firmware/firmware-manifest.json
  cat > $out/bin/a14-firmware <<EOF
  #!${python3}/bin/python3
  import runpy, sys
  sys.argv[0] = "$out/share/a14-firmware/firmware.py"
  runpy.run_path(sys.argv[0], run_name="__main__")
  EOF
  chmod +x $out/bin/a14-firmware
''
