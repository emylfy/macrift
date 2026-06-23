# Gruvbox Dark Hard — shell colors

# fzf
export FZF_DEFAULT_OPTS=" \
--color=bg+:#3c3836,bg:#1d2021,spinner:#d3869b,hl:#fb4934 \
--color=fg:#ebdbb2,header:#fb4934,info:#83a598,pointer:#d3869b \
--color=marker:#b8bb26,fg+:#ebdbb2,prompt:#83a598,hl+:#fb4934 \
--color=selected-bg:#504945 \
--color=border:#3c3836,label:#ebdbb2"

# bat — built-in to bat
export BAT_THEME="gruvbox-dark"

# zsh-autosuggestions (gray)
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE="fg=#928374"

# eza
export EZA_COLORS="\
di=1;34:\
ln=36:\
ex=1;32:\
fi=0:\
*.md=33:\
*.json=33:\
*.toml=33:\
*.yml=33:\
*.yaml=33:\
*.ts=34:\
*.js=33:\
*.py=32:\
*.rs=31:\
*.go=36:\
*.sh=32"

# fast-syntax-highlighting (applies after plugin loads via precmd hook)
_gruvbox_fsh() {
    [[ -z "${FAST_HIGHLIGHT_STYLES[*]+set}" ]] && return
    local t="${FAST_THEME_NAME}"

    # commands / builtins
    FAST_HIGHLIGHT_STYLES[${t}command]="fg=#83a598"            # aqua/blue
    FAST_HIGHLIGHT_STYLES[${t}builtin]="fg=#83a598"            # aqua/blue
    FAST_HIGHLIGHT_STYLES[${t}function]="fg=#83a598"           # aqua/blue
    FAST_HIGHLIGHT_STYLES[${t}alias]="fg=#b8bb26"              # green
    FAST_HIGHLIGHT_STYLES[${t}precommand]="fg=#b8bb26,italic"  # green
    FAST_HIGHLIGHT_STYLES[${t}unknown-token]="fg=#fb4934"      # red

    # arguments / paths
    FAST_HIGHLIGHT_STYLES[${t}path]="fg=#ebdbb2,underline"
    FAST_HIGHLIGHT_STYLES[${t}path_pathseparator]="fg=#8ec07c,underline"  # aqua
    FAST_HIGHLIGHT_STYLES[${t}globbing]="fg=#8ec07c"           # aqua
    FAST_HIGHLIGHT_STYLES[${t}single-hyphen-option]="fg=#fe8019"   # orange
    FAST_HIGHLIGHT_STYLES[${t}double-hyphen-option]="fg=#fe8019"   # orange

    # strings
    FAST_HIGHLIGHT_STYLES[${t}single-quoted-argument]="fg=#b8bb26"   # green
    FAST_HIGHLIGHT_STYLES[${t}double-quoted-argument]="fg=#b8bb26"   # green
    FAST_HIGHLIGHT_STYLES[${t}dollar-quoted-argument]="fg=#b8bb26"   # green
    FAST_HIGHLIGHT_STYLES[${t}back-quoted-argument]="fg=#d3869b"     # purple

    # variables / numbers
    FAST_HIGHLIGHT_STYLES[${t}variable]="fg=#fe8019"           # orange
    FAST_HIGHLIGHT_STYLES[${t}assign]="fg=#fe8019"             # orange
    FAST_HIGHLIGHT_STYLES[${t}numeric]="fg=#fabd2f"            # yellow

    # operators / separators
    FAST_HIGHLIGHT_STYLES[${t}commandseparator]="fg=#8ec07c"   # aqua
    FAST_HIGHLIGHT_STYLES[${t}redirection]="fg=#8ec07c"        # aqua
    FAST_HIGHLIGHT_STYLES[${t}reserved-word]="fg=#d3869b"      # purple
    FAST_HIGHLIGHT_STYLES[${t}comment]="fg=#928374"            # gray

    add-zsh-hook -d precmd _gruvbox_fsh
}
autoload -Uz add-zsh-hook
add-zsh-hook precmd _gruvbox_fsh
