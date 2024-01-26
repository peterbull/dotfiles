# Setup fzf
# ---------
if [[ ! "$PATH" == */home/peter-legion-wsl2/.fzf/bin* ]]; then
  PATH="${PATH:+${PATH}:}/home/peter-legion-wsl2/.fzf/bin"
fi

# Auto-completion
# ---------------
source "/home/peter-legion-wsl2/.fzf/shell/completion.bash"

# Key bindings
# ------------
source "/home/peter-legion-wsl2/.fzf/shell/key-bindings.bash"
