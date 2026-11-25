# osu!lazer — a game that owns its own configuration

Source ownership paths below are repository-relative. See the [desktop runbook](../nix.md) for operator actions.

`osu-lazer-bin` provides the upstream build. Its settings are plain files beside
`client.realm` in `~/.local/share/osu/`:

- `game.ini` contains settings-panel values.
- `framework.ini` pins window mode, resolution, renderer and volumes.
- `input.json` holds the input handlers, including the tablet's mapped area,
  rotation and pressure threshold.

`hosts/nix/hardware-policy.nix` configures the tablet. It installs
OpenTabletDriver for its udev rules and deliberately leaves its daemon disabled.

**None of those three can be home-manager files.** osu!framework writes every
config through `CreateFileSafely`, whose dispose path is
`storage.Delete(finalPath)` followed by `storage.Move(temporaryPath,
finalPath)`. The `Delete` unlinks whatever occupies the path, including a read-only
store symlink. The first clean exit thus replaces a managed link with a real
file. The next switch either fails on the unmanaged file or, if forced,
discards every setting changed in-game. There is no separate runtime override
file to preserve those edits.

`home.activation.osuSettings` in
`hosts/nix/modules/home/applications.nix` seeds these files instead. It copies
only absent files and leaves subsequent changes to the game.
**A partial file is enough.** osu!framework applies the keys it finds and keeps
its own defaults for the rest. It writes the full set on exit.

What `hosts/nix/dotfiles/gaming/osu/` carries is chosen around three things:

- **`game.ini` holds a live credential.** `Token` is an OAuth token for the
  logged-in account. This repository is public, so the seed excludes `Token`
  and `Username`. It also excludes `Skin` and `Ruleset`. These GUIDs refer to
  `client.realm` entries that do not exist in a fresh database.
  The seed also excludes the game's bookkeeping fields: `Version`,
  `ReleaseStream`, `WasSupporter`, `LastProcessedMetadataId`,
  `LastOnlineTagsPopulation`.
- **`input.json` is copied verbatim**. Each handler is resolved through
  a `$type` discriminator that must precede its object's other fields.
  An area of `50×28` at offset `186,116` on a 216×135 tablet
  cannot be reproduced by eye.
- **`framework.ini` is not seeded at all.** Resolution, display and renderer are
  what another machine most needs to choose for itself.

**Keybinds cannot be seeded separately.** `client.realm` is a binary Realm database,
schema-versioned and migrated per release. It contains `class_KeyBinding`,
`class_ModPreset`, `class_RulesetSetting`, skins, beatmaps and scores.
`strings client.realm` confirms what a given release stores there.
Preconfiguring any of these requires shipping a whole database.

The five `application/x-osu-*` MIME types are declared in `hosts/nix/modules/system/gaming.nix`,
because nixpkgs packages none of them. The desktop entry handles these types
and the URI scheme.
Only `x-scheme-handler/osu` is essential for browser links.
Without it, an `osu://` link from the browser has no handler.

## Mosu profile and library

`hosts/nix/pkgs/mosu.nix` pins Morasooma's official AppImage and disables its
self-updater. Its launcher uses a separate XDG data root, config root and
temporary directory. Home Manager seeds the same credential-free `game.ini`
and `input.json` in `~/.local/share/morasooma/mosu`; all later changes are
independent. This is profile separation, not a sandbox for untrusted code.
Never set either client's storage location to the other's profile.

For a one-time snapshot of maps, skins, collections, scores, and keybindings,
do this **before the first switch that installs Mosu**. Close both clients
and verify `xfs_info /home` reports `reflink=1`. In Fish, with vanilla using
its default storage location, run:

```fish
set vanilla "$HOME/.local/share/osu"
set mosu "$HOME/.local/share/morasooma"
test ! -e "$mosu/mosu"; and mkdir -p "$mosu"; and set stage (mktemp -d "$mosu/.library.XXXXXXXX"); and cp -R --reflink=always -- "$vanilla/files" "$stage/"; and cp -- "$vanilla/client.realm" "$stage/"; and mv -T --update=none-fail -- "$stage" "$mosu/mosu"
```

This publishes the snapshot only after both copies succeed, never replaces an
existing Mosu profile, and fails rather than silently making a full asset
copy when reflinks are unavailable. On failure, the `.library.*` staging
directory can be removed after inspection. Do not copy `game.ini`,
`storage.ini` or any login state from vanilla. After switching, launch
**Morasooma** and choose **Continue with this library** on the welcome
screen, not **Use my osu!lazer library**. Check maps and skins before
signing in, and configure audio and video in each client as needed.
If Mosu already has a profile, import `.osz` and `.osk` archives instead
of replacing its database.

New imports are not synchronized. After importing into both clients, close
them and deduplicate identical assets (not the databases or configs):

```fish
nix shell .#nixosConfigurations.nix.pkgs.jdupes -c jdupes -Br "$HOME/.local/share/osu/files" "$HOME/.local/share/morasooma/mosu/files"
```

The clients keep separate file entries and share only physical blocks.
Deleting an asset from one client leaves the other copy intact. Do not
symlink the `files/` trees together: each client prunes using its own database.
