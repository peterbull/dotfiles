#!/bin/bash
# Graceful shutdown for ctm-server

echo "Stopping ctm-server services..."

# Send Ctrl-C to each window to gracefully stop processes
tmux send-keys -t ctm-server:rails C-c
# tmux send-keys -t ctm-server:resque C-c
tmux send-keys -t ctm-server:resque-debug C-c
tmux send-keys -t ctm-server:scheduler C-c
tmux send-keys -t ctm-server:ctm-events C-c
tmux send-keys -t ctm-server:ctm-ai C-c
tmux send-keys -t ctm-server:ctm-chat C-c
tmux send-keys -t ctm-server:ctmcalls C-c
tmux send-keys -t ctm-server:nginx C-c
tmux send-keys -t ctm-server:pool C-c
tmux send-keys -t ctm-server:logs C-c
tmux send-keys -t ctm-server:ctm-ui C-c
tmux send-keys -t ctm-server:askctm C-c

# Wait a moment for graceful shutdown
sleep 4

# Stop docker containers (each repo runs its own compose)
for dir in ctm ctm-pool askctm ctm-nginx; do
  cd ~/work/$dir && docker compose down
  cd ~
done

# Kill the tmux session
tmux kill-session -t ctm-server

echo "ctm-server stopped"
