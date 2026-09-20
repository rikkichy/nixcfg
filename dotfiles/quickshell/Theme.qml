pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: theme
    // Material color roles; the fallback also makes first login usable before matugen.
    property var palette: ({})
    readonly property color surface: palette.surface || "#141218"
    readonly property color surfaceContainer: palette.surfaceContainer || "#211f26"
    readonly property color surfaceContainerHigh: palette.surfaceContainerHigh || "#2b2930"
    readonly property color surfaceContainerHighest: palette.surfaceContainerHighest || "#36343b"
    readonly property color textOnSurface: palette.onSurface || "#e6e0e9"
    readonly property color textOnSurfaceVariant: palette.onSurfaceVariant || "#cac4d0"
    readonly property color primary: palette.primary || "#d0bcff"
    readonly property color textOnPrimary: palette.onPrimary || "#381e72"
    readonly property color primaryContainer: palette.primaryContainer || "#4f378b"
    readonly property color textOnPrimaryContainer: palette.onPrimaryContainer || "#eaddff"
    readonly property color secondaryContainer: palette.secondaryContainer || "#4a4458"
    readonly property color textOnSecondaryContainer: palette.onSecondaryContainer || "#e8def8"
    readonly property color tertiary: palette.tertiary || "#efb8c8"
    readonly property color textOnTertiary: palette.onTertiary || "#492532"
    readonly property color tertiaryContainer: palette.tertiaryContainer || "#633b48"
    readonly property color textOnTertiaryContainer: palette.onTertiaryContainer || "#ffd8e4"
    readonly property color outline: palette.outline || "#938f99"
    readonly property color outlineVariant: palette.outlineVariant || "#49454f"
    readonly property color error: palette.error || "#ffb4ab"
    readonly property string fontFamily: "Google Sans Flex"
    property bool reducedMotion: Quickshell.env("QS_REDUCED_MOTION") === "1"
    readonly property int motionDuration: reducedMotion ? 0 : 200
    readonly property int radiusSmall: 12
    readonly property int radiusMedium: 20
    readonly property int radiusLarge: 28
    readonly property int radiusExtraLarge: 36

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
                theme.palette = next;
            } catch (error) {
                console.warn("Keeping last usable shell palette:", error);
            }
        }
    }
}
