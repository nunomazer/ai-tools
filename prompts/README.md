# Prompts

Reusable prompt templates and system instructions for AI assistants (Claude, ChatGPT, Gemini, Cursor, etc.).

Unlike the executable tools in this repo, prompts here are plain Markdown — copy/paste into the target agent's custom instructions, system prompt, or rules file.

## Contents

| Prompt | Purpose |
|--------|---------|
| [general-assistant/base-rules.md](general-assistant/base-rules.md) | General-purpose assistant persona — tone, formatting, response style. Not domain-specific. |

## Conventions

- One subdirectory per persona / use-case (`general-assistant/`, `coding-agent/`, `code-review/`, ...).
- Placeholders use `{{UPPERCASE}}` syntax, e.g. `{{METRIC OR IMPERIAL}}`.
- Each prompt file starts with a short "Use when" header describing its intended scope.
