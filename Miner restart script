#!/bin/bash

SESSION="nock-miner"
MINER_CMD="./target/release/nockchain-miner --your-flags-here"

# Check if session exists, create if not
tmux has-session -t $SESSION 2>/dev/null
if [ $? != 0 ]; then
  tmux new-session -d -s $SESSION "$MINER_CMD"
  echo "Started new tmux session with miner."
else
  # Restart miner inside existing session
  tmux send-keys -t $SESSION C-c
  sleep 1
  tmux send-keys -t $SESSION "$MINER_CMD" Enter
  echo "Restarted miner inside existing tmux session."
fi
