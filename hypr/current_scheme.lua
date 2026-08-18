-- Loads the live colour scheme.
--
-- scheme/current.lua is bootstrapped from scheme/default.lua by hyprland.lua
-- and rewritten by matugen on every wallpaper. If it is missing or half-written
-- a plain require() blows up, and because variables.lua interpolates colours
-- into strings the failure takes the *whole* variables module with it -- every
-- vars.* lookup downstream turns into nil and most of the config silently stops
-- loading. Fall back to the shipped default instead.

local ok, scheme = pcall(require, "scheme.current")

if ok and type(scheme) == "table" and scheme.primary then
    return scheme
end

return require("scheme.default")
