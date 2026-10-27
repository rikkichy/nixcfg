import json
import sys

import gi

gi.require_version("Gio", "2.0")
gi.require_version("GioUnix", "2.0")
from gi.repository import Gio, GioUnix, GLib


def visible(app, mode):
    tool = "X-DesktopTools" in (app.get_string_list("OnlyShowIn") or [])
    if mode == "tools":
        return tool and not app.get_nodisplay() and not app.get_is_hidden() and app.get_show_in("X-DesktopTools")
    return not tool and app.should_show()


try:
    if len(sys.argv) == 1:
        # Quickshell's index does not expose OnlyShowIn / NotShowIn / TryExec.
        apps = Gio.AppInfo.get_all()
        print(json.dumps({mode: [app.get_id() for app in apps
                                 if app.get_id() and visible(app, mode)]
                          for mode in ("apps", "tools")}))
    elif len(sys.argv) in (3, 4) and sys.argv[1] in ("apps", "tools"):
        mode, desktop_id = sys.argv[1:3]
        try:
            app = GioUnix.DesktopAppInfo.new(desktop_id)
        except TypeError:
            app = None
        if app is None or not visible(app, mode):
            raise ValueError("This entry is no longer available in this launcher")
        # GIO owns field-code expansion, working directories and Terminal=true.
        if len(sys.argv) == 4:
            action = sys.argv[3]
            if mode != "tools" or action not in app.list_actions():
                raise ValueError("This desktop action is no longer available")
            app.launch_action(action, None)
        elif not app.launch([], None):
            raise ValueError("The application could not be started")
    else:
        raise ValueError("Expected no arguments, or apps/tools followed by a desktop ID and optional action")
except (GLib.Error, ValueError) as error:
    print(str(error), file=sys.stderr)
    sys.exit(1)
