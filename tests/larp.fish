# Run with: fish --no-config tests/larp.fish /path/to/generated/larp.fish
source $argv[1]; or exit 1
set -gx TERM xterm-256color
set -gx COLORTERM truecolor

set -gx STARSHIP_CONFIG /original/starship.toml
set -gu fish_color_command blue --bold
set -gx fish_color_quote yellow
set -g fish_color_comment
set -e --global fish_color_param
set -l original (set --show STARSHIP_CONFIG fish_color_command fish_color_quote fish_color_comment fish_color_param | string collect)

larp; or exit 1
larp soviet; or exit 1
set -l prompt (starship prompt --path / --status 0)
string match -q '*soyuz-workstation*' -- $prompt; or exit 1

# Re-selecting must not replace the original snapshot with the active theme.
larp soviet; or exit 1

# Switching themes shares one snapshot and must replace both prompt and colors.
set -l soviet_config "$STARSHIP_CONFIG"
set -l soviet_command $fish_color_command
larp deep-space; or exit 1
set -l prompt (starship prompt --path / --status 0)
string match -q '*discovery*' -- $prompt; or exit 1
not string match -q '*soyuz-workstation*' -- $prompt; or exit 1
test "$STARSHIP_CONFIG" != "$soviet_config"; or exit 1
test "$fish_color_command" != "$soviet_command"; or exit 1
larp soviet; or exit 1
test "$STARSHIP_CONFIG" = "$soviet_config"; or exit 1
test "$fish_color_command" = "$soviet_command"; or exit 1
larp deep-space; or exit 1
set -l themed (set --show STARSHIP_CONFIG fish_color_command fish_color_quote fish_color_comment fish_color_param | string collect)
larp unknown 2>/dev/null
test $status -eq 2; or exit 1
larp soviet extra 2>/dev/null
test $status -eq 2; or exit 1
test "$themed" = "$(set --show STARSHIP_CONFIG fish_color_command fish_color_quote fish_color_comment fish_color_param)"; or exit 1

larp; or exit 1
test "$original" = "$(set --show STARSHIP_CONFIG fish_color_command fish_color_quote fish_color_comment fish_color_param)"; or exit 1
not set -q __larp_active; or exit 1

# An initially absent config must remain absent after the round trip.
set -e --global STARSHIP_CONFIG
larp deep-space; or exit 1
larp; or exit 1
not set -q --global STARSHIP_CONFIG; or exit 1
printf 'PASS: themed prompts, cross-theme switching, argument validation, and exact restoration\n'
