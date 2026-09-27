# prompts/

Archive of English Codex / manager prompts used for pull requests in this repository, kept for future review and handoff.

## Reconstruction note
PR **#1–#3** prompt files (`pr-0001` … `pr-0003`) are **reconstructed** from parent chat + `PROGRESS.md` / ADRs / phase docs when the original manager prompts were **not** archived live on the filesystem. They are labeled as reconstructions inside each file and must not be treated as verbatim originals. PR **#4–#5** were archived closer to the live prompts. PR **#6** (`pr-0006-m2-scoped-player-scaffold.md`) is archived from the live M2 scaffold prompt. PR **#7** (`pr-0007-m3-first-learning-loop.md`) is archived from the live M3 first-learning-loop prompt.

## Rules
- Engineering English only in this folder (prompt archives may quote HK Traditional Chinese UI strings that shipped in the product).
- Never put secrets, tokens, passwords, API keys, or private account details here.
- Never use Simplified Chinese.
- One markdown file per PR when practical: `pr-NNNN-<short-slug>.md`.
- Sanitize before pasting: strip credentials, machine-local absolute paths with private data, and anything not needed to reconstruct intent.
- When reconstructing: say so clearly at the top of the file (chat + PROGRESS), and prefer essential bullets over a full chat dump.

## How to add a file
1. Copy the essential manager / Codex prompt text used for that PR (or reconstruct and label it).
2. Fill the metadata block (date, branch, model, goal, constraints, acceptance, Mac mini notes).
3. Keep the file focused on what was asked — not a full chat dump.
