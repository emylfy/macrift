# Monokai — shell colors

# fzf
export FZF_DEFAULT_OPTS=" \
--color=bg+:#3e3d32,bg:#272822,spinner:#ae81ff,hl:#f92672 \
--color=fg:#f8f8f2,header:#f92672,info:#66d9ef,pointer:#ae81ff \
--color=marker:#a6e22e,fg+:#f8f8f2,prompt:#66d9ef,hl+:#f92672 \
--color=selected-bg:#49483e \
--color=border:#3e3d32,label:#f8f8f2"

# bat — built-in to bat
export BAT_THEME="Monokai Extended"

# zsh-autosuggestions (comment color)
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE="fg=#75715e"

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
_monokai_fsh() {
    [[ -z "${FAST_HIGHLIGHT_STYLES[*]+set}" ]] && return
    local t="${FAST_THEME_NAME}"

    # commands / builtins
    FAST_HIGHLIGHT_STYLES[${t}command]="fg=#66d9ef"            # cyan
    FAST_HIGHLIGHT_STYLES[${t}builtin]="fg=#66d9ef"            # cyan
    FAST_HIGHLIGHT_STYLES[${t}function]="fg=#66d9ef"           # cyan
    FAST_HIGHLIGHT_STYLES[${t}alias]="fg=#a6e22e"              # green
    FAST_HIGHLIGHT_STYLES[${t}precommand]="fg=#a6e22e,italic"  # green
    FAST_HIGHLIGHT_STYLES[${t}unknown-token]="fg=#f92672"      # red

    # arguments / paths
    FAST_HIGHLIGHT_STYLES[${t}path]="fg=#f8f8f2,underline"
    FAST_HIGHLIGHT_STYLES[${t}path_pathseparator]="fg=#fd971f,underline"  # orange
    FAST_HIGHLIGHT_STYLES[${t}globbing]="fg=#fd971f"           # orange
    FAST_HIGHLIGHT_STYLES[${t}single-hyphen-option]="fg=#fd971f"   # orange
    FAST_HIGHLIGHT_STYLES[${t}double-hyphen-option]="fg=#fd971f"   # orange

    # strings
    FAST_HIGHLIGHT_STYLES[${t}single-quoted-argument]="fg=#e6db74"   # yellow
    FAST_HIGHLIGHT_STYLES[${t}double-quoted-argument]="fg=#e6db74"   # yellow
    FAST_HIGHLIGHT_STYLES[${t}dollar-quoted-argument]="fg=#e6db74"   # yellow
    FAST_HIGHLIGHT_STYLES[${t}back-quoted-argument]="fg=#ae81ff"     # purple

    # variables / numbers
    FAST_HIGHLIGHT_STYLES[${t}variable]="fg=#ae81ff"           # purple
    FAST_HIGHLIGHT_STYLES[${t}assign]="fg=#ae81ff"             # purple
    FAST_HIGHLIGHT_STYLES[${t}numeric]="fg=#ae81ff"            # purple

    # operators / separators
    FAST_HIGHLIGHT_STYLES[${t}commandseparator]="fg=#f92672"   # red/pink
    FAST_HIGHLIGHT_STYLES[${t}redirection]="fg=#f92672"        # red/pink
    FAST_HIGHLIGHT_STYLES[${t}reserved-word]="fg=#f92672"      # red/pink
    FAST_HIGHLIGHT_STYLES[${t}comment]="fg=#75715e"            # comment

    add-zsh-hook -d precmd _monokai_fsh
}
autoload -Uz add-zsh-hook
add-zsh-hook precmd _monokai_fsh
