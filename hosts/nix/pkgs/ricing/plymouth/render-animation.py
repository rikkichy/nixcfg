"""Render the upstream QML indicator at exact timestamps, not from a recording."""

import sys
from pathlib import Path

from PySide6.QtCore import QUrl
from PySide6.QtGui import QColor, QGuiApplication, QSurfaceFormat
from PySide6.QtQuick import QQuickView

app = QGuiApplication([])
format = QSurfaceFormat()
format.setAlphaBufferSize(8)
QSurfaceFormat.setDefaultFormat(format)
view = QQuickView()
view.setColor(QColor("transparent"))
view.setSource(QUrl.fromLocalFile(str(Path(sys.argv[1]).resolve())))
if view.status() == QQuickView.Status.Error:
    raise RuntimeError("\n".join(error.toString() for error in view.errors()))

indicator = view.rootObject()
indicator.setProperty("running", False)
indicator.setProperty("size", 96)
indicator.setProperty("color", QColor("#a8c7fa"))
view.resize(96, 96)
view.show()
app.processEvents()
view.grabWindow()  # Initialize the shader's profile texture before sampling.

output = Path(sys.argv[2])
output.mkdir(parents=True, exist_ok=True)
for frame in range(1092):  # 4.55 seconds at 240 Hz; no duplicate endpoint.
    indicator.setProperty("elapsed", frame * 1000 / 240)
    app.processEvents()
    image = view.grabWindow()
    if image.isNull() or image.pixelColor(48, 48).alpha() != 255:
        raise RuntimeError(f"QML indicator did not render at frame {frame}")
    if not image.save(str(output / f"throbber-{frame:04d}.png")):
        raise RuntimeError(f"Could not save frame {frame}")
view.close()
