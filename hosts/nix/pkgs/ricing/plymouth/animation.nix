{
  lib,
  fetchzip,
  runCommand,
  python3,
  qt6,
  mesa,
  xvfb-run,
}:

let
  revision = "3cf182586c6c948a6ae61b15df13ff1365c0dab0";
  source = fetchzip {
    url = "https://github.com/duxlabs-dev/dux-qml-common/archive/${revision}.tar.gz";
    hash = "sha256-bZqeOW6WZdBqhXsYgo2WUPbegIsOmx5eof8SGutGApc=";
  };
  python = python3.withPackages (ps: [ ps.pyside6 ]);
in
runCommand "plymouth-expressive-animation"
  {
    nativeBuildInputs = [ python qt6.qtshadertools xvfb-run ];
    QT_PLUGIN_PATH = "${qt6.qtbase}/${qt6.qtbase.qtPluginPrefix}";
    QML_IMPORT_PATH = "${qt6.qtdeclarative}/${qt6.qtbase.qtQmlPrefix}";
    QT_QPA_PLATFORM = "xcb";
    QT_XCB_GL_INTEGRATION = "xcb_glx";
    QSG_RHI_BACKEND = "opengl";
    QSG_RENDER_LOOP = "basic";
    QT_SCALE_FACTOR = "1";
    LIBGL_ALWAYS_SOFTWARE = "true";
    LIBGL_DRIVERS_PATH = "${mesa}/lib/dri";
    LD_LIBRARY_PATH = lib.makeLibraryPath [ mesa ];
    meta = {
      description = "Material 3 Expressive frames rendered directly from Quickshell QML";
      homepage = "https://github.com/duxlabs-dev/dux-qml-common";
      license = with lib.licenses; [ mit asl20 ];
      platforms = lib.platforms.linux;
    };
  }
  ''
    mkdir -p Widgets Shaders/qsb
    cp ${source}/DCommon/Widgets/{DLoadingIndicator.qml,MaterialShapes.js,MaterialShapeData.js,DLogoShape.js} Widgets/
    # Remove shell theme dependencies, not the shape, spring or shader implementation.
    # 3640ms steady rotation makes the seven-shape 4550ms loop exactly three turns.
    # Let the spring settle instead of snapping its rotation at the 10% threshold.
    substituteInPlace Widgets/DLoadingIndicator.qml \
      --replace-fail 'import qs.DCommon.Common' "" \
      --replace-fail 'property color containerColor: Style.primaryContainer' 'property color containerColor: "#a8c7fa"' \
      --replace-fail 'property color color: contained ? Style.onPrimaryContainer : Style.primary' 'property color color: "#a8c7fa"' \
      --replace-fail 'radius: Style.fullRadius(width, height)' 'radius: width / 2' \
      --replace-fail 'readonly property int rotationDuration: 4666' 'readonly property int rotationDuration: 3640' \
      --replace-fail 'readonly property real visibilityThreshold: 0.1' 'readonly property real visibilityThreshold: 0.001'
    qsb --glsl '100 es,120,150' \
      -o Shaders/qsb/loading_indicator.frag.qsb \
      ${source}/DCommon/Shaders/frag/loading_indicator.frag
    export XDG_RUNTIME_DIR="$TMPDIR/runtime"
    mkdir -m700 "$XDG_RUNTIME_DIR"
    xvfb-run -a python ${./render-animation.py} Widgets/DLoadingIndicator.qml "$out"
    license="$out/share/licenses/expressive-animation"
    install -Dm644 ${source}/LICENSE "$license/MIT"
    cp ${source}/DCommon/Widgets/{MaterialShapes.NOTICE,Apache-2.0.txt} "$license/"
  ''
