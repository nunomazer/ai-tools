#!/usr/bin/env bash
# Test stub for the `claude` binary. Prints the resolved CLAUDE_CONFIG_DIR
# (so tests can assert resolution) then the completion marker (so claude-loop
# exits after a single iteration). Ignores all CLI args.
echo "FAKE_CLAUDE_CONFIG_DIR=[${CLAUDE_CONFIG_DIR:-<unset>}]"
echo "<<<TASK_COMPLETE>>>"
