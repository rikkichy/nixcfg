# osu!lazer — a game that owns its own configuration

`osu-lazer-bin`, the upstream build. Its settings are plain files beside
`client.realm` in `~/.local/share/osu/`: `game.ini` is the settings panel,
`framework.ini` pins window mode, resolution, renderer and volumes, and
`input.json` holds the input handlers — including the tablet's mapped area,
rotation and pressure threshold. The tablet itself is arranged in
`hosts/nix/hardware-policy.nix`, where OpenTabletDriver is installed for its udev rules and
its daemon deliberately left off.

**None of those three can be home-manager files.** osu!framework writes every
config through `CreateFileSafely`, whose dispose path is
`storage.Delete(finalPath)` followed by `storage.Move(temporaryPath,
finalPath)`. The `Delete` unlinks whatever sits at the path, a read-only store
symlink included, so the first clean exit replaces a managed link with a real
file — and the next switch either fails on the now-unmanaged file or, forced,
discards every setting changed in-game. There is no separate runtime override
file to preserve those edits.

So `home.activation.osuSettings` in
`hosts/nix/modules/home/applications.nix` seeds them instead, copying only what is
absent and leaving everything afterwards to the game, the same arrangement
Equicord's `settings.json` has. **A partial file is enough** — osu!framework
applies the keys it finds and keeps its own defaults for the rest, then writes
the full set back on exit.

What `hosts/nix/dotfiles/gaming/osu/` carries is chosen around three things:

- **`game.ini` holds a live credential.** `Token` is an OAuth token for the
  logged-in account and this repo is public, so it and `Username` are stripped,
  along with `Skin` and `Ruleset` — GUIDs into `client.realm`, naming nothing
  against a fresh database — and the game's own bookkeeping (`Version`,
  `ReleaseStream`, `WasSupporter`, `LastProcessedMetadataId`,
  `LastOnlineTagsPopulation`).
- **`input.json` is copied verbatim**, because each handler is resolved through
  a `$type` discriminator that has to lead its object. It is also the half
  worth having: an area of `50×28` at offset `186,116` on a 216×135 tablet
  cannot be reproduced by eye.
- **`framework.ini` is not seeded at all.** Resolution, display and renderer are
  what another machine most needs to choose for itself.

**Keybinds are out of reach.** `client.realm` is a binary Realm database,
schema-versioned and migrated per release, and `class_KeyBinding` lives there
along with `class_ModPreset`, `class_RulesetSetting`, skins, beatmaps and
scores. `strings client.realm` is enough to confirm what a given release keeps
there; nothing short of shipping a whole database preconfigures any of it.

The five `application/x-osu-*` MIME types are declared in `hosts/nix/modules/system/gaming.nix`,
because nixpkgs packages none of them and the desktop entry handles those plus the URI scheme.
Only `x-scheme-handler/osu` is load-bearing — an `osu://` link from the browser
has nowhere to go without it.
