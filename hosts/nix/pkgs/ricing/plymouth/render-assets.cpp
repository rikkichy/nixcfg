#include <QCoreApplication>
#include <QDomDocument>
#include <QFile>
#include <QImage>
#include <QPainter>
#include <QSvgRenderer>

static void render(const QByteArray &svg, const char *path, QSize size, QColor color)
{
    QSvgRenderer renderer(svg);
    if (!renderer.isValid())
        qFatal("Invalid SVG for %s", path);
    QImage image(size, QImage::Format_ARGB32_Premultiplied);
    if (image.isNull())
        qFatal("Cannot allocate %s", path);
    image.fill(Qt::transparent);
    QPainter painter(&image);
    renderer.render(&painter);
    painter.end();

    bool opaque = false;
    bool transparent = false;
    for (int y = 0; y < image.height(); ++y) {
        const auto *row = reinterpret_cast<const QRgb *>(image.constScanLine(y));
        for (int x = 0; x < image.width(); ++x) {
            const QRgb pixel = row[x];
            const int alpha = qAlpha(pixel);
            opaque |= alpha == 255;
            transparent |= alpha == 0;
            // Compare premultiplied channels: antialiased edges retain the intended color.
            const QRgb expected = qPremultiply(qRgba(color.red(), color.green(), color.blue(), alpha));
            if (qAbs(qRed(pixel) - qRed(expected)) > 1
                || qAbs(qGreen(pixel) - qGreen(expected)) > 1
                || qAbs(qBlue(pixel) - qBlue(expected)) > 1)
                qFatal("Unexpected SVG color in %s", path);
        }
    }
    if (!opaque || !transparent || !image.save(QString::fromLatin1(path)))
        qFatal("Invalid alpha or cannot save %s", path);
}

int main(int argc, char **argv)
{
    QCoreApplication app(argc, argv);
    if (argc != 2)
        qFatal("usage: render-assets MATERIAL_LOCK.svg");
    QFile lock(QString::fromLocal8Bit(argv[1]));
    QDomDocument icon;
    if (!lock.open(QIODevice::ReadOnly) || !icon.setContent(&lock))
        qFatal("Cannot read Material lock SVG");
    auto root = icon.documentElement();
    if (root.tagName() != "svg")
        qFatal("Material lock document is not an SVG");
    root.setAttribute("fill", "#a8c7fa");
    const QByteArray lockSvg = icon.toByteArray();
    const QColor primary("#a8c7fa");
    render(lockSvg, "material-lock.png", QSize(96, 96), primary);
    render(lockSvg, "lock.png", QSize(48, 48), primary);
    render(R"(<svg xmlns="http://www.w3.org/2000/svg" width="96" height="96"><path d="M24 49 L41 66 L73 30" fill="none" stroke="#a8c7fa" stroke-width="8" stroke-linecap="round" stroke-linejoin="round"/></svg>)",
           "unlock-success.png", QSize(96, 96), primary);
    // Material 3 Expressive medium shape: 56px field with a 2px focus stroke.
    render(R"(<svg xmlns="http://www.w3.org/2000/svg" width="368" height="56"><rect x="1" y="1" width="366" height="54" rx="11" fill="none" stroke="#a8c7fa" stroke-width="2"/></svg>)",
           "entry.png", QSize(368, 56), primary);
    render(R"(<svg xmlns="http://www.w3.org/2000/svg" width="12" height="12"><circle cx="6" cy="6" r="3" fill="#e3e2e6"/></svg>)",
           "bullet.png", QSize(12, 12), QColor("#e3e2e6"));
}
