# Cache sudo credentials upfront so sub-windows don't prompt
sudo -v

# Start a new tmux session named "ctm-server" with the first window for rails
tmux new-session -d -s ctm-server -n "rails"

# Ensure docker dependencies are running first, then start rails
tmux send-keys -t ctm-server:rails "cd ~/work/ctm && docker compose up -d && CTM_UI_HMR=1 ASKCTM_HMR=1 ./bin/debug.sh" C-m

# # Create new window for resque (jobs queue)
# tmux new-window -t ctm-server -n "resque"
# tmux send-keys -t ctm-server:resque "cd ~/work/ctm && ./bin/pool" C-m
# debug single worker
tmux new-window -t ctm-server -n "resque-debug"
tmux send-keys -t ctm-server:resque-debug "cd ~/work/ctm && RUBY_DEBUG_FORK_MODE=child QUEUE=* bundle exec rdbg -n -O --port 38699 -c -- bundle exec rake resque:work" C-m

# Create new window for resque scheduler
tmux new-window -t ctm-server -n "scheduler"
tmux send-keys -t ctm-server:scheduler "cd ~/work/ctm && ./bin/new_scheduler.sh" C-m

# Create new window for ctm-events (ws comms to phonetrac)
tmux new-window -t ctm-server -n "ctm-events"
tmux send-keys -t ctm-server:ctm-events "cd ~/work/ctm-events && npm ci && ./bin/run.sh" C-m

# Create new window for ctmcalls (ngrok ws -> inflow)
tmux new-window -t ctm-server -n "ctmcalls"
tmux send-keys -t ctm-server:ctmcalls "cd ~/work/ctm && ctmcalls" C-m

# Create new window for voiceai/chataiv1
tmux new-window -t ctm-server -n "ctm-chat"
tmux send-keys -t ctm-server:ctm-chat "cd ~/work/ctm-chat && npm ci && ./bin/run.sh" C-m

# Create new window for live transcriptions
tmux new-window -t ctm-server -n "ctm-ai"
tmux send-keys -t ctm-server:ctm-ai "cd ~/work/ctm-ai && npm ci && ./bin/run.sh" C-m

# Create new window for nginx
tmux new-window -t ctm-server -n "nginx"
tmux send-keys -t ctm-server:nginx "cd ~/work/ctm-nginx && rake" C-m

# Create new window for pool
tmux new-window -t ctm-server -n "pool"
tmux send-keys -t ctm-server:pool "cd ~/work/ctm-pool && ./bin/app.sh run" C-m

# Create new window for logs
tmux new-window -t ctm-server -n "logs"
tmux send-keys -t ctm-server:logs "cd ~/work/ctm && tail -f log/development.log | grep LLOG" C-m

# new window for ctmui
tmux new-window -t ctm-server -n "ctm-ui"
tmux send-keys -t ctm-server:ctm-ui "cd ~/work/ctm/packages/ctm-ui && pnpm dev" C-m

tmux new-window -t ctm-server -n "askctm"
tmux send-keys -t ctm-server:askctm "cd ~/work/askctm && pnpm dev" C-m



# Select the first window (rails) when attaching
tmux select-window -t ctm-server:rails
