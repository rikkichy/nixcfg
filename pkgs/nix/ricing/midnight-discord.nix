{
  lib,
  fetchurl,
}:

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
