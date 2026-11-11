{ runCommandCC }:

runCommandCC "waydroid-pinch" { meta.mainProgram = "waydroid-pinch"; } ''
  mkdir -p "$out/bin"
  $CC -O2 -Wall -Wextra -Werror -o "$out/bin/waydroid-pinch" ${./main.c} -lm
''
