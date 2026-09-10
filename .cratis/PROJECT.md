# StudioIssues — project context

The public issue tracker for Cratis Studio — the collaborative environment
for designing, visualizing, and editing Screenplay event models. Issue
comments, labels, and closure require separate exact authorization; there is
no application code here.

## The public boundary

Everything here is world-readable. Never bring private Studio repository
context into public output: no source excerpts, no infrastructure specifics,
no secret names or posture, no internal URLs or API response bodies. What
belongs here: the user-visible symptom, when it happens, what the user sees
instead of what they should, and what was decided.

## AI-assisted development

This repository uses the Cratis AI contract:

- **`.cratis/ai.json`** records the subscription — `cratis/documentation` plus the language-agnostic `cratis/engineering/core` cell.
- **`.cratis/PROJECT.md`** (this file) is the canonical project context; the root `AGENTS.md`, `CLAUDE.md`, and `GEMINI.md` are minimal bootstraps that point here and do nothing else.
- There is **no local AI corpus and no generated tool adapters** in this repository. Shared skills arrive through the Cratis AI marketplace plugins (Claude Code, Codex, GitHub Copilot, Cursor, and Pi are installable today — see the [harness guide](https://www.cratis.io/ai/harnesses/)).

For contributors:

1. Install the Cratis plugin for your harness once (per the harness guide); the subscribed profiles' skills then load automatically when tasks match.
2. General, reusable improvements are proposed in [`Cratis/AI`](https://github.com/Cratis/AI) — never copied into, or synchronized from, this repository.
3. Repository-specific facts and conventions belong in this file; repository-local skills live under `.agents/skills/`.
4. AI session work records (plans, handovers, session notes, scratch analyses) stay in the untracked `.ai-work/` folder and never enter git; a durable follow-up becomes a GitHub issue.
