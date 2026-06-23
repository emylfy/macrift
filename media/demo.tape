# media/demo.tape — reproducible source for media/demo.gif (the README hero).
#
# "Slideshow" tour: show the main menu once, then each section's submenu back to
# back. The transitions (back to main, move, enter) run inside Hide blocks, so
# the main menu never flickers between sections. Browse only — it just opens each
# submenu and backs out, never selects a leaf action, so nothing is applied.
#
# Render:
#   brew install vhs          # pulls ttyd; ffmpeg already required by vhs
#   vhs media/demo.tape       # writes media/demo.gif

Output media/demo.gif

Set Shell "zsh"
Set FontFamily "FiraCode Nerd Font"
Set FontSize 20
Set Theme "Catppuccin Mocha"
Set Width 490
Set Height 580
Set Padding 20
Set TypingSpeed 55ms

# Hidden setup: keep `macrift` on PATH and skip the update check, then clear.
Hide
Type "export PATH=$HOME/.local/bin:$PATH; export MACRIFT_NO_UPDATE=true"
Enter
Type "clear"
Enter
Show

Sleep 700ms

# Launch — visible — and hold on the main menu once.
Type "macrift"
Sleep 400ms
Enter
Sleep 2700ms

# System Tweaks (enter hidden, show the submenu).
Hide
Enter
Sleep 900ms
Show
Sleep 1900ms

# Apps & Packages (hop via main menu, hidden).
Hide
Left
Sleep 450ms
Down
Sleep 250ms
Enter
Sleep 900ms
Show
Sleep 1900ms

# Customize
Hide
Left
Sleep 450ms
Down
Sleep 250ms
Enter
Sleep 900ms
Show
Sleep 1900ms

# Security & Privacy
Hide
Left
Sleep 450ms
Down
Sleep 250ms
Enter
Sleep 900ms
Show
Sleep 1900ms

# Cleanup
Hide
Left
Sleep 450ms
Down
Sleep 250ms
Enter
Sleep 900ms
Show
Sleep 1900ms

# Manage Plugins (built-in — add / update / remove plugins)
Hide
Left
Sleep 450ms
Down
Sleep 250ms
Enter
Sleep 900ms
Show
Sleep 2100ms
