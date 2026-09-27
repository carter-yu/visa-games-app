# prompts/

Archive of English Codex / manager prompts used for pull requests in this repository, kept for future review and handoff.

## Rules
- Engineering English only in this folder (prompt archives may quote HK Traditional Chinese UI strings that shipped in the product).
- Never put secrets, tokens, passwords, API keys, or private account details here.
- Never use Simplified Chinese.
- One markdown file per PR when practical: `pr-NNNN-<short-slug>.md`.
- Sanitize before pasting: strip credentials, machine-local absolute paths with private data, and anything not needed to reconstruct intent.

## How to add a file
1. Copy the essential manager / Codex prompt text used for that PR.
2. Fill the metadata block (date, branch, model, goal, constraints, acceptance, Mac mini notes).
3. Keep the file focused on what was asked — not a full chat dump.
