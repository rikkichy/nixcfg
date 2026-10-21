// Sample the upstream QML indicator at exact timestamps, not from a recording.
#include <QDir>
#include <QFileInfo>
#include <QGuiApplication>
#include <QImage>
#include <QQmlError>
#include <QQuickItem>
#include <QQuickView>
#include <QSurfaceFormat>
#include <QUrl>
#include <QVariant>

int main(int argc, char **argv)
{
    QSurfaceFormat format;
    format.setAlphaBufferSize(8);
    QSurfaceFormat::setDefaultFormat(format);
    QGuiApplication app(argc, argv);
    if (argc != 3)
        qFatal("usage: render-animation INDICATOR.qml OUTPUT_DIRECTORY");

    const QColor color("#a8c7fa");
    QQuickView view;
    view.setColor(Qt::transparent);
    view.setSource(QUrl::fromLocalFile(QFileInfo(argv[1]).absoluteFilePath()));
    if (view.status() != QQuickView::Ready) {
        for (const auto &error : view.errors())
            qCritical("%s", qPrintable(error.toString()));
        return 1;
    }
    auto *indicator = view.rootObject();
    if (!indicator || !indicator->setProperty("running", false)
        || !indicator->setProperty("size", 96)
        || !indicator->setProperty("color", color))
        qFatal("Cannot configure QML indicator");
    view.resize(96, 96);
    view.show();
    app.processEvents();
    view.grabWindow(); // Initialize the shader's profile texture before sampling.

    const QDir output(QString::fromLocal8Bit(argv[2]));
    if (!output.mkpath("."))
        qFatal("Cannot create frame directory");
    for (int frame = 0; frame < 1092; ++frame) { // 4.55 seconds at 240 Hz, no duplicate endpoint.
        if (!indicator->setProperty("elapsed", frame * 1000.0 / 240.0))
            qFatal("Cannot set timestamp at frame %d", frame);
        app.processEvents();
        const QImage image = view.grabWindow();
        if (image.isNull() || image.size() != QSize(96, 96)
            || image.pixelColor(48, 48).alpha() != 255)
            qFatal("QML indicator did not render at frame %d", frame);
        if (!image.save(output.filePath(QString("throbber-%1.png").arg(frame, 4, 10, QLatin1Char('0')))))
            qFatal("Cannot save frame %d", frame);
    }
    view.close();
}
