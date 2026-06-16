# AI Tools

Collection of tools and utilities for AI coding agents and IDEs.

## Tools

| Tool | Agent/IDE | Description |
|------|-----------|-------------|
| [claude-statusline](claude-statusline/) | Claude Code | Custom two-line status line with session info, token usage, and quota monitoring. Multi-account aware via `CLAUDE_CONFIG_DIR` |
| [claude-loop](claude-loop/) | Claude Code | Headless *Ralph loop* runner that survives subscription quota limits — sleeps until the window resets (fixed delay or target time) and resumes the same session. Multi-account aware |
| [prompts](prompts/) | Any | Reusable prompt templates and system instructions (personas, rules, response styles) |

## Installation

Each tool has its own installation instructions. Navigate to the tool's directory and follow the `README.md`.

Some tools include an `install.sh` script for automated setup:

```bash
cd claude-statusline
./install.sh
```

## Requirements

Vary per tool — check each tool's `README.md`. Common ones:

- Python 3.10+ (claude-statusline)
- Bash + GNU coreutils (claude-loop)
- Git

## License

MIT
