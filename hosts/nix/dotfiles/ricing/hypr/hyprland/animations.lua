hl.config({
    animations = {
        enabled = true,
    },
})

-- M3 Expressive fast spatial: damping coefficient = 2 * ratio * sqrt(stiffness * mass).
-- Hyprland 0.56 calls it "dampening"; springs ignore speed and settle physically.
hl.curve("expressiveSpatial", { type = "spring", mass = 1, stiffness = 800, dampening = 2 * 0.6 * math.sqrt(800) })
-- Heavier damping keeps full-screen paging from bouncing across monitor edges.
hl.curve("expressivePaging", { type = "spring", mass = 1, stiffness = 800, dampening = 2 * 0.85 * math.sqrt(800) })
hl.curve("emphasizedAccel", { type = "bezier", points = { { 0.3, 0 }, { 0.8, 0.15 } } })
hl.curve("emphasizedDecel", { type = "bezier", points = { { 0.05, 0.7 }, { 0.1, 1 } } })
hl.curve("standard", { type = "bezier", points = { { 0.2, 0 }, { 0, 1 } } })

hl.animation({ leaf = "layersIn", enabled = true, speed = 1.8, bezier = "emphasizedDecel", style = "slide" })
hl.animation({ leaf = "layersOut", enabled = true, speed = 1.2, bezier = "emphasizedAccel", style = "slide" })
hl.animation({ leaf = "fadeLayersIn", enabled = true, speed = 1.2, bezier = "standard" })
hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = 1.2, bezier = "emphasizedAccel" })

-- A visible launch pop, with a much shorter shrink-away exit.
hl.animation({ leaf = "windowsIn", enabled = true, speed = 1, spring = "expressiveSpatial", style = "popin 80%" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 1.4, bezier = "emphasizedAccel", style = "popin 92%" })
hl.animation({ leaf = "windowsMove", enabled = true, speed = 2.4, bezier = "emphasizedDecel" })

-- Special workspaces enter from the left and retreat to the same edge.
hl.animation({ leaf = "workspaces", enabled = true, speed = 1, spring = "expressivePaging", style = "slidevert" })
hl.animation({ leaf = "specialWorkspaceIn", enabled = true, speed = 2.4, bezier = "emphasizedDecel", style = "slide left" })
hl.animation({ leaf = "specialWorkspaceOut", enabled = true, speed = 1.6, bezier = "emphasizedAccel", style = "slide right" })

hl.animation({ leaf = "fade", enabled = true, speed = 1.6, bezier = "standard" })
hl.animation({ leaf = "fadeIn", enabled = true, speed = 1.2, bezier = "standard" })
hl.animation({ leaf = "fadeOut", enabled = true, speed = 1.4, bezier = "emphasizedAccel" })
hl.animation({ leaf = "border", enabled = true, speed = 1.6, bezier = "standard" })
