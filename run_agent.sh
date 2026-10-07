#!/usr/bin/env bash
export PATH="/home/ubuntu/.opencode/bin:/home/ubuntu/.local/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
PROMPT_CONTENT=$(cat "/home/ubuntu/srv-codex/worktrees/task-017/prompt.txt")
opencode --auto --prompt "$PROMPT_CONTENT"
EXIT_CODE=$?
echo "OpenCode exited with code $EXIT_CODE"
if [ $EXIT_CODE -ne 0 ]; then
    sleep 30
fi
