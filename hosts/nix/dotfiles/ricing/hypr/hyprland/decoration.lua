local vars = require("variables")

hl.config({
    decoration = {
        rounding = vars.windowRounding,
        wobble = { enabled = true, intensity = 0.16, stiffness = 265, damping = 13.8 },

        blur = {
            enabled           = vars.blurEnabled,
            xray              = vars.blurXray,
            special           = vars.blurSpecialWs,
            popups            = vars.blurPopups,
            input_methods     = vars.blurInputMethods,
            size              = vars.blurSize,
            passes            = vars.blurPasses,
        },

        shadow = { enabled = vars.shadowEnabled },
    },
})
