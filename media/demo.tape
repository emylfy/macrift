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

# Rendered at 2x (FontSize/Width/Height/Padding all doubled vs the on-screen grid)
# so the GIF stays crisp when GitHub scales it down via the README width.
Set Shell "zsh"
Set FontFamily "FiraCode Nerd Font"
Set FontSize 40
# GitHub Dark Dimmed (official Primer palette) — soft grey-blue, not pure black.
Set Theme {"background":"#22272e","foreground":"#adbac7","cursor":"#539bf5","selection":"#2e3c51","black":"#545d68","red":"#f47067","green":"#57ab5a","yellow":"#c69026","blue":"#539bf5","magenta":"#b083f0","cyan":"#39c5cf","white":"#909dab","brightBlack":"#636e7b","brightRed":"#ff938a","brightGreen":"#6bc46d","brightYellow":"#daaa3f","brightBlue":"#6cb6ff","brightMagenta":"#dcbdfb","brightCyan":"#56d4dd","brightWhite":"#cdd9e5"}
Set Width 980
Set Height 1160
Set Padding 40
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
