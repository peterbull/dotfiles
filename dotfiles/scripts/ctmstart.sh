#!/bin/bash
# Starts the CTM dev stack in the "ctm-server" tmux session, one window per service.

# Cache sudo credentials upfront so sub-windows don't prompt
sudo -v

# Opens a window that runs the command inside a shell, so the window and its output survive a crash.
start_window() {
  local name="$1" command="$2"
  tmux new-window -t ctm-server -n "$name"
  tmux send-keys -t "ctm-server:$name" "$command" C-m
}

# Development config/ctm.yml reads LiveKit and bridge settings for call capture from these variables.
ctm_env='{ [ ! -f .env.live-conversation.local ] || { set -a; source .env.live-conversation.local; set +a; }; }'

tmux new-session -d -s ctm-server -n "rails"
# Ensure docker dependencies are running first, then start rails
tmux send-keys -t ctm-server:rails "cd ~/work/ctm && $ctm_env && docker compose up -d && CTM_UI_HMR=1 ASKCTM_HMR=1 ./bin/debug.sh" C-m

# start_window resque "cd ~/work/ctm && ./bin/pool"
start_window resque-debug "cd ~/work/ctm && $ctm_env && RUBY_DEBUG_FORK_MODE=child QUEUE=* bundle exec rdbg -n -O --port 38699 -c -- bundle exec rake resque:work"
# es_publisher exits after repeated publish errors and foreman then stops the whole scheduler,
# so hold the scheduler until the freshly started Elasticsearch container answers.
start_window scheduler "cd ~/work/ctm && until curl -fsS 'http://localhost:9200/_cluster/health?wait_for_status=yellow&timeout=5s' >/dev/null 2>&1; do echo 'scheduler: waiting for Elasticsearch on :9200'; sleep 3; done && ./bin/new_scheduler.sh"
start_window ctm-events "cd ~/work/ctm-events && npm ci && ./bin/run.sh"
start_window ctmcalls "cd ~/work/ctm && ctmcalls"
start_window ctm-chat "cd ~/work/ctm-chat && npm ci && ./bin/debug.sh"
start_window ctm-ai "cd ~/work/ctm-ai && npm ci && ./bin/run.sh"
start_window nginx "cd ~/work/ctm-nginx && rake"
start_window pool "cd ~/work/ctm-pool && ./bin/app.sh run"
start_window logs "cd ~/work/ctm && tail -f log/development.log | grep LLOG"
start_window ctm-ui "cd ~/work/ctm/packages/ctm-ui && pnpm dev"
start_window ctm-ui-storybook "cd ~/work/ctm/packages/ctm-ui && pnpm dev:storybook"
start_window askctm "cd ~/work/askctm && pnpm dev"

# LiveKit voice stack (~/work/conversations): server on :7880, Twilio stream bridge on :8089, testground on :3001.
if [ -d ~/work/conversations ]; then
  start_window livekit "cd ~/work/conversations && pnpm dev:livekit"
  start_window livekit-transcribe "cd ~/work/conversations && pnpm dev:transcribe"
  start_window livekit-elevenlabs "cd ~/work/conversations && pnpm dev:elevenlabs"
  start_window livekit-operators "cd ~/work/conversations && pnpm dev:agent"
  start_window livekit-bridge "cd ~/work/conversations && pnpm dev:bridge"
  # Public wss endpoint Twilio streams to (peterbull-bridge.ngrok.app -> :8089); named tunnel in the ngrok config.
  start_window bridge-tunnel "ngrok start conversation-bridge"
  start_window livekit-testground "cd ~/work/conversations && pnpm dev:testground"
else
  echo "Skipping LiveKit services: ~/work/conversations is missing" >&2
fi

# Synthetic customer MCP over HTTP (127.0.0.1:7391/mcp); token lives in the repo .env.
if [ -f ~/work/synthetic-user/dist/cli.js ]; then
  start_window synthetic-mcp 'cd ~/work/synthetic-user && node --env-file=.env --env-file="$HOME/.env" dist/cli.js mcp --http --config config.local.json'
else
  echo "Skipping synthetic-mcp: ~/work/synthetic-user/dist/cli.js is missing" >&2
fi

tmux select-window -t ctm-server:rails
