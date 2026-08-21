{
  lib,
  fetchurl,
}:

# refact0r's Midnight, the Discord theme the generated palette is painted onto.
# The whole theme is one built stylesheet, so this is a file rather than a
# package: home.nix concatenates it into the matugen template that overrides
# its colour variables.
#
# Pinned to a commit rather than to `refact0r.github.io/.../build/midnight.css`,
# which is what the theme's own installation instructions @import. That URL is
# rebuilt from master, so it would change what this machine renders with
# nothing here moving -- and an @import is fetched at every Discord start,
# where this file is fetched once and then lives in the store.
fetchurl {
  name = "midnight-discord.css";

  url = "https://raw.githubusercontent.com/refact0r/midnight-discord/151176d321c8feb08f939fad0c69693947b73dda/build/midnight.css";
  hash = "sha256-+VTFyp2y9FywZ0jpMIwJ3I+80QZ8SNn2uq976whyLf0=";

  meta = {
    description = "Dark, rounded Discord theme driven by CSS custom properties";
    homepage = "https://github.com/refact0r/midnight-discord";
    license = lib.licenses.mit;
    platforms = lib.platforms.all;
  };
}
