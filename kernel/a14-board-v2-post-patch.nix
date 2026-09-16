# Selective board-v2 backport, after the retained platform/display recipe
# and before the camera/video DT appends. See docs/BOARD-V2-BACKPORT.md.
''
      echo "Applying ASUS A14 v2 board power, USB repeater and EC reset fixes"
      patch --batch --forward --fuzz=0 -p1 < ${../patches/board-v2/01-power-supplies.patch}
      patch --batch --forward --fuzz=0 -p1 < ${../patches/board-v2/02-usb-repeaters.patch}
      patch --batch --forward --fuzz=0 -p1 < ${../patches/board-v2/03-ec-reset.patch}
''
