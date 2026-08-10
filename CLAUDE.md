# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Code comments & design decisions

- Zero explanatory comments in code by default. Add JSDoc only when needed to explain a non-obvious helper/utility function — not elsewhere.
- Design/architecture decisions belong in the plan/ticket (`plans/.../tickets/`), never as a code comment.
- When a design/architecture question comes up mid-task, research it and explain it at that point. Once it's settled and recorded in the ticket, don't re-explain or re-narrate it — that's wasted tokens.

## Response style (token economy)

- No step narration: skip "now I'll do X" before each tool call; keep end-of-turn summaries to 1-2 lines, don't restate the diff in prose.
- Prefer pointers over pasting code: reference existing code by `file:line`, don't paste the block back into the response.
- Explain only when asked: report what changed; only justify the "why" if the user asks or it's a genuine design question (see rule above).
- No inline TODO/FIXME: pending work becomes a ticket in the plan, never a loose marker in code.

## Pull Requests

Merging means the change is complete. A PR description must not contain a "Test plan" (or any checklist) with pending/unchecked items — if something still needs to happen after merge, it isn't done, and it doesn't belong being merged yet. Only describe what was actually done and verified before opening the PR. Follow-up work that's still pending goes in a ticket file (`plans/.../tickets/0N-*.md`), never as an open checkbox in the PR body.
