# Setup fzf
# ---------
if [[ ! "$PATH" == */home/pete-00/.fzf/bin* ]]; then
  PATH="${PATH:+${PATH}:}/home/pete-00/.fzf/bin"
fi

# Auto-completion
# ---------------
[[ $- == *i* ]] && source "/home/pete-00/.fzf/shell/completion.bash" 2> /dev/null

# Key bindings
# ------------
source "/home/pete-00/.fzf/shell/key-bindings.bash"
