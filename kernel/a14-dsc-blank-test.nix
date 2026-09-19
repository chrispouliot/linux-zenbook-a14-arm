# Applied after the recorded display stack; disabled unless its boot flag is set.
''
  patch --batch --forward --fuzz=0 -p1 < ${../patches/a14-dsc-defer-sink-clear-test.patch}
  patch --batch --forward --fuzz=0 -p1 < ${../patches/a14-dsc-d3-before-source-test.patch}
  patch --batch --forward --fuzz=0 -p1 < ${../patches/a14-dsc-early-d3-test.patch}
''
