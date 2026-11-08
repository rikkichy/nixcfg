pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: theme
    property var palette: ({})
    // Displayed colors blend from this snapshot toward `palette` while `morph` runs to 1.
    property var previousPalette: ({})
    property real morph: 1
    // Color Behaviors stand aside while the palette morphs: per-frame retargeting would hold them still.
    readonly property bool morphing: morph < 1
    // ExpressiveButton scales by this; a new palette drives one shared bounce.
    property real popScale: 1
    readonly property var fallbacks: ({
            surface: "#141218",
            surfaceContainer: "#211f26",
            surfaceContainerHigh: "#2b2930",
            surfaceContainerHighest: "#36343b",
            onSurface: "#e6e0e9",
            onSurfaceVariant: "#cac4d0",
            primary: "#d0bcff",
            onPrimary: "#381e72",
            secondaryContainer: "#4a4458",
            onSecondaryContainer: "#e8def8",
            tertiary: "#efb8c8",
            tertiaryContainer: "#633b48",
            onTertiaryContainer: "#ffd8e4",
            outline: "#938f99",
            outlineVariant: "#49454f",
            error: "#ffb4ab"
        })
    readonly property color surface: role("surface")
    readonly property color surfaceContainer: role("surfaceContainer")
    readonly property color surfaceContainerHigh: role("surfaceContainerHigh")
    readonly property color surfaceContainerHighest: role("surfaceContainerHighest")
    readonly property color textOnSurface: role("onSurface")
    readonly property color textOnSurfaceVariant: role("onSurfaceVariant")
    readonly property color primary: role("primary")
    readonly property color textOnPrimary: role("onPrimary")
    readonly property color secondaryContainer: role("secondaryContainer")
    readonly property color textOnSecondaryContainer: role("onSecondaryContainer")
    readonly property color tertiary: role("tertiary")
    readonly property color tertiaryContainer: role("tertiaryContainer")
    readonly property color textOnTertiaryContainer: role("onTertiaryContainer")
    readonly property color outline: role("outline")
    readonly property color outlineVariant: role("outlineVariant")
    readonly property color error: role("error")
    readonly property string fontFamily: "Google Sans Flex"
    property bool reducedMotion: Quickshell.env("QS_REDUCED_MOTION") === "1"
    readonly property int motionDuration: reducedMotion ? 0 : 200
    readonly property int radiusSmall: 12
    readonly property int radiusMedium: 20
    readonly property int radiusLarge: 28
    readonly property int radiusExtraLarge: 36

    function role(key) {
        const target = Qt.color(palette[key] || fallbacks[key]);
        if (morph >= 1)
            return target;
        const start = Qt.color(previousPalette[key]);
        return Qt.rgba(start.r + (target.r - start.r) * morph, start.g + (target.g - start.g) * morph,
                       start.b + (target.b - start.b) * morph, 1);
    }

    function show(next) {
        const changed = JSON.stringify(next) !== JSON.stringify(palette);
        const animate = changed && Object.keys(palette).length > 0 && !reducedMotion;
        if (animate) {
            // Start from what is on screen, including a morph that is still running.
            const shown = {};
            for (const key in fallbacks)
                shown[key] = role(key).toString();
            previousPalette = shown;
        }
        morphAnimation.stop();
        morph = animate ? 0 : 1;
        palette = next;
        if (animate) {
            morphAnimation.start();
            popAnimation.restart();
        }
    }

    NumberAnimation {
        id: morphAnimation
        target: theme
        property: "morph"
        to: 1
        duration: 220
        easing.type: Easing.BezierSpline
        easing.bezierCurve: [0.2, 0, 0, 1, 1, 1]
    }
    // Quick squeeze, then an elastic release that overshoots past rest before landing.
    SequentialAnimation {
        id: popAnimation
        NumberAnimation {
            target: theme
            property: "popScale"
            to: 0.88
            duration: 90
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: theme
            property: "popScale"
            to: 1
            duration: 420
            easing.type: Easing.OutElastic
            easing.amplitude: 1
            easing.period: 0.4
        }
    }

    FileView {
        id: colors
        path: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/quickshell/colors.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const next = JSON.parse(text());
                for (const key in next) {
                    if (!/^#[0-9a-fA-F]{6}$/.test(next[key]))
                        throw new Error("Invalid color role: " + key);
                }
                theme.show(next);
            } catch (error) {
                console.warn("Keeping last usable shell palette:", error);
            }
        }
    }
}
