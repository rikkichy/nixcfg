hl.config({
    animations = {
        enabled = true,
    },
})

hl.curve("specialWorkSwitch", { type = "bezier", points = { { 0.05, 0.7 }, { 0.1, 1 } } })
hl.curve("emphasizedAccel", { type = "bezier", points = { { 0.3, 0 }, { 0.8, 0.15 } } })
hl.curve("emphasizedDecel", { type = "bezier", points = { { 0.05, 0.7 }, { 0.1, 1 } } })
hl.curve("standard", { type = "bezier", points = { { 0.2, 0 }, { 0, 1 } } })

-- `speed` is the animation's duration in ds (1 ds = 100 ms), so a smaller
-- number is a faster animation. Most leaves sit at 0.6x the Hyprland defaults,
-- the same factor as the shell's own animation duration scale,
-- so window motion and shell motion agree; Hyprland has no global multiplier,
-- so the factor is applied per leaf.
--
-- `layersIn` is quicker than that factor. It is the appearance of every layer
-- surface -- the launcher and the pickers above all -- which answer a keypress
-- and want to be on screen by the time the first character is typed. A layer
-- rule can name a style, as rules.lua does, but carries no speed of its own, so
-- this leaf is where their timing is set.
hl.animation({ leaf = "layersIn", enabled = true, speed = 1.8, bezier = "emphasizedDecel", style = "slide" })
hl.animation({ leaf = "layersOut", enabled = true, speed = 2.4, bezier = "emphasizedAccel", style = "slide" })
hl.animation({ leaf = "fadeLayers", enabled = true, speed = 3, bezier = "standard" })

hl.animation({ leaf = "windowsIn", enabled = true, speed = 3, bezier = "emphasizedDecel" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 1.8, bezier = "emphasizedAccel" })
hl.animation({ leaf = "windowsMove", enabled = true, speed = 3.6, bezier = "standard" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 3, bezier = "standard" })

hl.animation({
    leaf    = "specialWorkspace",
    enabled = true,
    speed   = 2.4,
    bezier  = "specialWorkSwitch",
    style   = "slidefadevert 15%"
})
hl.animation({ leaf = "fade", enabled = true, speed = 3.6, bezier = "standard" })
hl.animation({ leaf = "fadeDim", enabled = true, speed = 3.6, bezier = "standard" })
hl.animation({ leaf = "border", enabled = true, speed = 3.6, bezier = "standard" })
