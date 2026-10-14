# osu!lazer — a game that owns its own configuration

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
Equicord's `settings.json` uses the same arrangement.
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
