# fish config (used inside kitty; bash stays the login shell).

fish_add_path ~/.local/bin

# eza — modern ls
alias ls='eza --icons --group-directories-first'
alias ll='eza --icons --group-directories-first -lh --git'
alias la='eza --icons --group-directories-first -lha --git'
alias tree='eza --icons --tree'

# bat — syntax-highlighted cat
alias cat='bat --pager=never'
set -gx MANPAGER "sh -c 'col -bx | bat -l man -p'"

# git
alias grep='grep --color=auto'
alias diff='diff --color=auto'
alias lg='lazygit'
set -gx GIT_PAGER delta

# yazi — cd into the directory you quit yazi in
function ya
    set tmp (mktemp -t "yazi-cwd.XXXXXX")
    yazi $argv --cwd-file=$tmp
    if set cwd (command cat -- $tmp); and test -n "$cwd"; and test "$cwd" != "$PWD"
        cd -- $cwd
    end
    rm -f -- $tmp
end

command -v zoxide >/dev/null; and zoxide init fish | source
command -v starship >/dev/null; and starship init fish | source
