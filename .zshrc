# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# If you come from bash you might have to change your $PATH.
# export PATH=$HOME/bin:$HOME/.local/bin:/usr/local/bin:$PATH

# Path to your Oh My Zsh installation.
export ZSH="$HOME/.oh-my-zsh"

# Set name of the theme to load --- if set to "random", it will
# load a random theme each time Oh My Zsh is loaded, in which case,
# to know which specific one was loaded, run: echo $RANDOM_THEME
# See https://github.com/ohmyzsh/ohmyzsh/wiki/Themes
ZSH_THEME="robbyrussell"

# Set list of themes to pick from when loading at random
# Setting this variable when ZSH_THEME=random will cause zsh to load
# a theme from this variable instead of looking in $ZSH/themes/
# If set to an empty array, this variable will have no effect.
# ZSH_THEME_RANDOM_CANDIDATES=( "robbyrussell" "agnoster" )

# Uncomment the following line to use case-sensitive completion.
# CASE_SENSITIVE="true"

# Uncomment the following line to use hyphen-insensitive completion.
# Case-sensitive completion must be off. _ and - will be interchangeable.
# HYPHEN_INSENSITIVE="true"

# Uncomment one of the following lines to change the auto-update behavior
# zstyle ':omz:update' mode disabled  # disable automatic updates
# zstyle ':omz:update' mode auto      # update automatically without asking
# zstyle ':omz:update' mode reminder  # just remind me to update when it's time

# Uncomment the following line to change how often to auto-update (in days).
# zstyle ':omz:update' frequency 13

# Uncomment the following line if pasting URLs and other text is messed up.
# DISABLE_MAGIC_FUNCTIONS="true"

# Uncomment the following line to disable colors in ls.
# DISABLE_LS_COLORS="true"

# Uncomment the following line to disable auto-setting terminal title.
# DISABLE_AUTO_TITLE="true"

# Uncomment the following line to enable command auto-correction.
# ENABLE_CORRECTION="true"

# Uncomment the following line to display red dots whilst waiting for completion.
# You can also set it to another string to have that shown instead of the default red dots.
# e.g. COMPLETION_WAITING_DOTS="%F{yellow}waiting...%f"
# Caution: this setting can cause issues with multiline prompts in zsh < 5.7.1 (see #5765)
# COMPLETION_WAITING_DOTS="true"

# Uncomment the following line if you want to disable marking untracked files
# under VCS as dirty. This makes repository status check for large repositories
# much, much faster.
# DISABLE_UNTRACKED_FILES_DIRTY="true"

# Uncomment the following line if you want to change the command execution time
# stamp shown in the history command output.
# You can set one of the optional three formats:
# "mm/dd/yyyy"|"dd.mm.yyyy"|"yyyy-mm-dd"
# or set a custom format using the strftime function format specifications,
# see 'man strftime' for details.
# HIST_STAMPS="mm/dd/yyyy"

# Would you like to use another custom folder than $ZSH/custom?
# ZSH_CUSTOM=/path/to/new-custom-folder

# Which plugins would you like to load?
# Standard plugins can be found in $ZSH/plugins/
# Custom plugins may be added to $ZSH_CUSTOM/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
# Add wisely, as too many plugins slow down shell startup.
plugins=(
  git
  docker
  docker-compose
)



source $ZSH/oh-my-zsh.sh

# get secrets
if [ -f ~/.secrets ]; then
    source ~/.secrets
fi

# Set personal aliases, overriding those provided by Oh My Zsh libs,
# plugins, and themes. Aliases can be placed here, though Oh My Zsh
# users are encouraged to define aliases within a top-level file in
# the $ZSH_CUSTOM folder, with .zsh extension. Examples:
# - $ZSH_CUSTOM/aliases.zsh
# - $ZSH_CUSTOM/macos.zsh
# For a full list of active aliases, run `alias`.
#
# Example aliases
# alias zshconfig="mate ~/.zshrc"
# alias ohmyzsh="mate ~/.oh-my-zsh"



# never beep
setopt NO_BEEP

ZSH_THEME="powerlevel10k/powerlevel10k"
source /opt/homebrew/share/powerlevel10k/powerlevel10k.zsh-theme

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

source <(fzf --zsh)

export GOPATH=$HOME/go
export GOBIN=$GOPATH/bin
export PATH=$PATH:/usr/local/go/bin:$GOBIN


export NVM_DIR="$HOME/.nvm"
  [ -s "/opt/homebrew/opt/nvm/nvm.sh" ] && \. "/opt/homebrew/opt/nvm/nvm.sh"  # This loads nvm
  [ -s "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm" ] && \. "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm" 

nvm alias default 24 &> /dev/null

export EDITOR=nvim
export PATH="$HOME/.local/share/bob/nvim-bin:$PATH"


# Aliases

## Docker
alias dup="docker compose up -d"
alias ddown="docker compose down"
alias dlog="docker compose logs -f"
alias dbuild="docker compose build"

## Editor launches
alias n="nvim ."
alias nc="cd ~/.config/nvim && nvim ~/.config/nvim"
alias nz="nvim ~/.zshrc"
alias nd="nvim --cmd \"lua init_debug=true\""
alias np="nvim ~/.plan"
alias c="code ."

## python
alias va="source .venv/bin/activate"

## Rust
alias cb="cargo build"
alias cr="RUST_BACKTRACE=1 cargo run"
alias crf="RUST_BACKTRACE=full cargo run"
alias ca="cargo build && RUST_BACKTRACE=1 cargo run"
alias caf="cargo build && RUST_BACKTRACE=full cargo run"


## Zig
alias zb="zig build"

## Git
alias gpc='gh pr create --fill'
alias gpm='gh pr merge --squash --delete-branch'
alias gpc-telus='gh pr create --fill && sleep 25 && gh pr merge --squash --delete-branch'
alias gs-apply='git stash apply $(git stash list | fzf | awk "{print \$1}" | tr -d ":")'; 

# force push to current branch
unalias gpf 2>/dev/null
gpf() {
  local branch
  branch=$(git branch --show-current)
  if [[ "$branch" == "main" || "$branch" == "master" ]]; then
    echo "ERROR: tried to push to a no-no branch, checkout a dev branch"
    return 1
  fi
  git push -u origin "$branch" --force-with-lease
}


## immediate stash and apply for a quick local save point
gsarchive() {
  local timestamp=$(TZ="America/New_York" date '+%Y-%m-%d %H:%M:%S EST')
  local message="${*:-ARCHIVE: archive snapshot $timestamp}"
  git stash save -u "$message" && git stash apply
}

alias ghs='gh auth switch'
alias gsa="gsarchive"

unalias grepdiff 2>/dev/null
grepdiff() {
  local search_term="${1:-console.log}"
  git diff HEAD --name-only | while read file; do
    if grep -q "$search_term" "$file" 2>/dev/null; then
      echo "=== $file ==="
      grep -B 3 -A 3 "$search_term" "$file"
      echo ""
    fi
  done
}

unalias dirdump_flat 2>/dev/null
dirdump_flat() {
    find . -maxdepth 1 -type f \( \
        ! -name "*.lock" -a \
        ! -name "package-lock.json" -a \
        ! -name "yarn.lock" -a \
        ! -name "pnpm-lock.yaml" -a \
        ! -name "bun.lockb" -a \
        ! -name "deno.lock" -a \
        ! -name "uv.lock" -a \
        ! -name "*.plan" -a \
        ! -name "*.ipynb" -a \
        ! -name "Pipfile.lock" -a \
        ! -name "poetry.lock" -a \
        ! -name "Cargo.lock" -a \
        ! -name "composer.lock" -a \
        ! -name "go.sum" -a \
        ! -name "*.log" -a \
        ! -name "*.tmp" -a \
        ! -name "*.cache" -a \
        ! -name ".DS_Store" -a \
        ! -name "Thumbs.db" -a \
        ! -name "*.pyc" -a \
        ! -name "*.pyo" -a \
        ! -name "*.so" -a \
        ! -name "*.dll" -a \
        ! -name "*.exe" -a \
        ! -name "*.o" -a \
        ! -name "*.a" -a \
        ! -name "*.class" -a \
        ! -name "*.wasm" -a \
        ! -name "*.map" -a \
        ! -name ".env" -a \
        ! -name ".env.local" -a \
        ! -name ".env.*.local" -a \
        ! -name "swagger.json" -a \
        ! -name "swagger.yml" -a \
        ! -name "swagger.yaml" -a \
        ! -name "openapi.json" -a \
        ! -name "openapi.yml" -a \
        ! -name "openapi.yaml" -a \
        ! -name "*.md" -a \
        ! -name "*.png" -a \
        ! -name "*.jpg" -a \
        ! -name "*.jpeg" -a \
        ! -name "*.gif" -a \
        ! -name "*.svg" -a \
        ! -name "*.ico" -a \
        ! -name "*.webp" -a \
        ! -name "*.tldr" -a \
        ! -name "*.config.js" -a \
        ! -name "*.config.ts" -a \
        ! -name ".gitignore" -a \
        ! -name ".gitattributes" -a \
        ! -name ".editorconfig" -a \
        ! -name ".prettierrc*" -a \
        ! -name ".eslintrc*" -a \
        ! -name "README*" -a \
        ! -name "LICENSE*" -a \
        ! -name "CHANGELOG*" -a \
        ! -name "CONTRIBUTING*" \
    \) -print | while read -r file; do
        echo "## ${file#./}"
        echo
        cat "$file"
        echo
        echo
    done | pbcopy
}

unalias dirdump_all 2>/dev/null
dirdump_all() {
    find . -type d \( \
        -name ".git" -o \
        -name ".venv" -o \
        -name "venv" -o \
        -name "env" -o \
        -name "__pycache__" -o \
        -name "node_modules" -o \
        -name "dist" -o \
        -name "build" -o \
        -name ".next" -o \
        -name ".nuxt" -o \
        -name ".svelte-kit" -o \
        -name "target" -o \
        -name "vendor" -o \
        -name ".cache" -o \
        -name ".tmp" -o \
        -name "tmp" -o \
        -name ".uv" -o \
        -name ".deno" -o \
        -name "deno_modules" -o \
        -name ".bun" -o \
        -name "bun_modules" -o \
        -name ".pnpm-store" -o \
        -name ".turbo" -o \
        -name ".nx" -o \
        -name "coverage" -o \
        -name ".coverage" -o \
        -name ".pytest_cache" -o \
        -name ".mypy_cache" -o \
        -name ".ruff_cache" -o \
        -name ".tox" -o \
        -name "htmlcov" -o \
        -name ".husky" -o \
        -name ".vscode" -o \
        -name ".idea" -o \
        -name "bin" -o \
        -name "obj" -o \
        -name "out" -o \
        -name ".gradle" -o \
        -name ".maven" -o \
        -name ".m2" -o \
        -name "cmake-build-*" -o \
        -name ".cmake" -o \
        -name "CMakeFiles" -o \
        -name ".stack-work" -o \
        -name "_build" -o \
        -name "elm-stuff" -o \
        -name ".terraform" -o \
        -name ".ansible" -o \
        -name "logs" -o \
        -name "log" \
    \) -prune -o -type f \( \
        ! -name "*.lock" -a \
        ! -name "package-lock.json" -a \
        ! -name "yarn.lock" -a \
        ! -name "pnpm-lock.yaml" -a \
        ! -name "bun.lockb" -a \
        ! -name "deno.lock" -a \
        ! -name "uv.lock" -a \
        ! -name "Pipfile.lock" -a \
        ! -name "poetry.lock" -a \
        ! -name "Cargo.lock" -a \
        ! -name "composer.lock" -a \
        ! -name "go.sum" -a \
        ! -name "*.log" -a \
        ! -name "*.tmp" -a \
        ! -name "*.cache" -a \
        ! -name ".DS_Store" -a \
        ! -name "Thumbs.db" -a \
        ! -name "*.pyc" -a \
        ! -name "*.pyo" -a \
        ! -name "*.so" -a \
        ! -name "*.dll" -a \
        ! -name "*.exe" -a \
        ! -name "*.o" -a \
        ! -name "*.a" -a \
        ! -name "*.class" -a \
        ! -name "*.wasm" -a \
        ! -name "*.map" -a \
        ! -name ".env" -a \
        ! -name ".env.local" -a \
        ! -name ".env.*.local" -a \
        ! -name "swagger.json" -a \
        ! -name "swagger.yml" -a \
        ! -name "swagger.yaml" -a \
        ! -name "openapi.json" -a \
        ! -name "openapi.yml" -a \
        ! -name "openapi.yaml" -a \
        ! -name "*.md" -a \
        ! -name "*.png" -a \
        ! -name "*.jpg" -a \
        ! -name "*.jpeg" -a \
        ! -name "*.gif" -a \
        ! -name "*.svg" -a \
        ! -name "*.ico" -a \
        ! -name "*.webp" -a \
        ! -name "*.tldr" -a \
        ! -name "*.plan" -a \
        ! -name "*.ipynb" -a \
        ! -name "*.config.js" -a \
        ! -name "*.config.ts" -a \
        ! -name ".gitignore" -a \
        ! -name ".gitattributes" -a \
        ! -name ".editorconfig" -a \
        ! -name ".prettierrc*" -a \
        ! -name ".eslintrc*" -a \
        ! -name "README*" -a \
        ! -name "LICENSE*" -a \
        ! -name "CHANGELOG*" -a \
        ! -name "CONTRIBUTING*" \
    \) -print | while read -r file; do
        echo "## ${file#./}"
        echo
        cat "$file"
        echo
        echo
    done | pbcopy
}


create_issue_checkout_branch() {
  if [[ -z "$1" ]]; then
    echo "Please provide an issue name as a parameter"
    echo "Usage: create_issue_ckout_branch <title> [description]"
    return 1
  fi
  local output=$(gh issue create --assignee @me -t "$1" -b "${2:-}")
  local issue_number=$(echo "$output" | awk -F'/' '{print $NF}')
  gh issue develop $issue_number --checkout
}
alias ghc="create_issue_checkout_branch"

#
## Gen purpose aliases 
alias zr="source ~/.zshrc && echo 'shell session reset'"
alias tf="tree | tee >(pbcopy)"
alias t1="tree -L 1 | tee >(pbcopy)"
alias t2="tree -L 2 | tee >(pbcopy)"
alias t3="tree -L 3 | tee >(pbcopy)"
alias t4="tree -L 4 | tee >(pbcopy)"

clipdump() {
	local dir="${1:-.}"
	find "$dir" -type f -print0 | xargs -0 cat | pbcopy
	echo "Contents of files in '$dir' copied to clipboard"
}

alias clp="clipdump"
alias lg="lazygit"
alias work="~/shift-projects"
alias peter="~/peter-projects"




# Homebrew Ruby (brew install ruby)
export PATH="/opt/homebrew/opt/ruby@3.4/bin:$PATH"
export PATH="/opt/homebrew/lib/ruby/gems/3.4.0/bin:$PATH"
# Python Path
export PATH="/opt/homebrew/opt/python@3.12/bin:$PATH"
export PATH="/opt/homebrew/opt/postgresql@15/bin:$PATH"
# python alias
alias python="python3"

# NVM version
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
# nvm use default



# pnpm
export PNPM_HOME="/Users/peterbull/Library/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac
# pnpm end
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

# Turn off annoying accented char suggestion on macos.
# Note: On the first run this won't work, you have to log out and
# log back in.
# defaults write -g ApplePressAndHoldEnabled -bool false



# Created by `pipx` on 2025-01-15 19:08:15
export PATH="$PATH:/Users/peterbull/.local/bin"

# Added by LM Studio CLI (lms)
export PATH="$PATH:/Users/peterbull/.lmstudio/bin"

# tab binds to suggestions
bindkey '^I' complete-word

# ctrl and space to do default "tab" behavior
bindkey '^ ' complete-word

# Stop 10k prompt from appearing
typeset -g POWERLEVEL9K_INSTANT_PROMPT=quiet
source $(brew --prefix)/share/zsh-autosuggestions/zsh-autosuggestions.zsh

source $(brew --prefix)/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

# Macos -- make app switcher appear on all screens
# defaults write com.apple.Dock appswitcher-all-displays -bool true; killall Dock



export PATH="/opt/homebrew/opt/postgresql@16/bin:$PATH"

# export PATH="$HOME/.local/zig:$PATH"
export PATH="$HOME/.zvm/bin:$HOME/.zvm/self:$PATH"

export PATH=$PATH:$HOME/.luarocks/bin

autoload -U +X bashcompinit && bashcompinit
complete -o nospace -C /opt/homebrew/bin/terraform terraform
source <(kubectl completion zsh)


alias lzd='lazydocker'

alias kfwd="sudo -E kubefwd svc -n default --tui"

export PYENV_ROOT="$HOME/.pyenv"
[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"

bindkey -v
bindkey -M viins 'jk' vi-cmd-mode


alias pib='bash ~/peter-projects/pi-config/sandbox/run-msb.sh'
#
# >>> microsandbox >>>
export PATH="$HOME/.microsandbox/bin:$PATH"
export DYLD_LIBRARY_PATH="$HOME/.microsandbox/lib${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}"
# <<< microsandbox <<<
# The following lines have been added by Docker Desktop to enable Docker CLI completions.
fpath=(/Users/peterbull/.docker/completions $fpath)
autoload -Uz compinit
compinit
# End of Docker CLI completions
#
eval "$(mise activate zsh)"
. "/Users/peterbull/.deno/env"
eval "$(mise activate zsh)"
