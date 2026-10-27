import json
import sys

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib


try:
    if len(sys.argv) == 1:
        # Quickshell's index does not expose OnlyShowIn / NotShowIn / TryExec.
        print(json.dumps([app.get_id() for app in Gio.AppInfo.get_all()
                          if app.get_id() and app.should_show()]))
    elif len(sys.argv) == 2:
        app = Gio.DesktopAppInfo.new(sys.argv[1])
        if app is None or not app.should_show():
            raise ValueError("This application is no longer available")
        # GIO owns field-code expansion, working directories and Terminal=true.
        if not app.launch([], None):
            raise ValueError("The application could not be started")
    else:
        raise ValueError("Expected a desktop-entry ID or no arguments")
except (GLib.Error, ValueError) as error:
    print(str(error), file=sys.stderr)
    sys.exit(1)
