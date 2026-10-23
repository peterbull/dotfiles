#!/bin/bash
# Graceful shutdown for ctm-server

echo "Stopping ctm-server services..."

# Send Ctrl-C to every window ctmstart.sh opened (and any added since) to stop processes gracefully.
tmux list-windows -t ctm-server -F '#{window_id}' | while read -r window; do
  tmux send-keys -t "$window" C-c
done

# Wait for every window to return to its shell and for the resque debugger port to close;
# a lingering rdbg on 38699 breaks the next resque worker's forked jobs.
busy_windows() {
  tmux list-panes -s -t ctm-server -F '#{window_name} #{pane_pid} #{pane_current_command}' 2>/dev/null |
    while read -r name pid command; do
      case "$command" in
        zsh|bash|sh|fish) pgrep -P "$pid" >/dev/null && echo "$name: $(pgrep -P "$pid" -l | head -1)" ;;
        *) echo "$name: $command" ;;
      esac
    done
}

busy=""
for _ in $(seq 1 30); do
  busy=$(busy_windows)
  if [ -z "$busy" ] && ! lsof -nP -iTCP:38699 -sTCP:LISTEN >/dev/null 2>&1; then
    break
  fi
  sleep 1
done
if [ -n "$busy" ]; then
  echo "Still running after 30s (closing the session anyway):"
  echo "$busy"
fi
if lsof -nP -iTCP:38699 -sTCP:LISTEN >/dev/null 2>&1; then
  echo "Warning: port 38699 is still held; stop the leftover rdbg before the next ctmstart:"
  lsof -nP -iTCP:38699 -sTCP:LISTEN
fi

# Stop docker containers (each repo runs its own compose)
for dir in ctm ctm-pool askctm ctm-nginx; do
  cd ~/work/$dir && docker compose down
  cd ~
done

# Kill the tmux session
tmux kill-session -t ctm-server

echo "ctm-server stopped"
