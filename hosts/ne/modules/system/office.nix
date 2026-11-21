{ lib, pkgs, ... }:

let
  apps = {
    Word = {
      version = "16.115.26111533";
      sha256 = "5ac9129c878fa04466aec509d47e9dcf86638dd13b5bf55b84b2e0da6392930c";
    };
    Excel = {
      version = "16.115.26110837";
      sha256 = "de94b56243d96210c65188fc6d23dc0e1614d6746765c14584e6451b61607eff";
    };
    PowerPoint = {
      version = "16.115.26111533";
      sha256 = "7a2adf3064225a6461c24563ec11bf5766e547228ff2b64c9a1d6e1cb17ea2f1";
    };
  };

  choices = pkgs.writeText "office-install-choices.plist" (
    lib.generators.toPlist { escape = true; } [
      {
        choiceIdentifier = "com.microsoft.autoupdate";
        choiceAttribute = "selected";
        attributeSetting = 0;
      }
    ]
  );

  install =
    app:
    { version, sha256 }:
    let
      pkg = pkgs.fetchurl {
        url = "https://res.public.onecdn.static.microsoft/mro1cdnstorage/C1297A47-86C4-4C1F-97FA-950631F94777/MacAutoupdate/Microsoft_${app}_${version}_Installer.pkg";
        inherit sha256;
      };
    in
    "installOfficeApp ${
      lib.escapeShellArgs [
        app
        version
        pkg
      ]
    }";
in
{
  # The installer skips AutoUpdate, but an existing copy can still update Office.
  system.defaults.CustomUserPreferences."com.microsoft.autoupdate2" = {
    HowToCheck = "Manual";
    EnableCheckForUpdatesButton = false;
  };

  system.activationScripts.postActivation.text = lib.mkAfter ''
    installOfficeApp() {
      local app="$1" version="$2" pkg="$3"
      local info="/Applications/Microsoft $app.app/Contents/Info.plist"
      if [[ -f "$info" && "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info")" == "$version" ]]; then
        return 0
      fi

      /usr/sbin/installer -pkg "$pkg" -target / -applyChoiceChangesXML ${choices} || return
      if [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info")" != "$version" ]]; then
        printf >&2 'Microsoft %s did not install the pinned build %s.\n' "$app" "$version"
        return 1
      fi
    }
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList install apps)}
  '';
}
