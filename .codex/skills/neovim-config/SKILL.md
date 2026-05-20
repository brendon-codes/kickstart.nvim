---
name: neovim-config
description: Use when working on Neovim configuration, especially Kickstart.nvim customization, init.lua changes, lua/custom/settings.lua edits, custom Lua settings, keymaps, plugins, LSP, diagnostics, UI tweaks, or project-agent behavior for preserving upstream Kickstart.nvim updateability.
---

# Neovim Project Agent

Use this skill when making or reviewing changes in `~/.config/nvim/`.

## Workflow

- Read the local `AGENTS.md` before changing the Neovim config.
- Inspect the existing custom module style before adding new functions or patterns.
- Prefer extending `lua/custom/settings.lua` for custom settings, keymaps, autocmds, diagnostics, UI tweaks, LSP customizations, plugin behavior, and other local behavior changes.
- Avoid modifying `init.lua` unless the change cannot reasonably be reached from the custom config.
- If `init.lua` must change, keep the edit minimal and focused on requiring or calling functions defined in `lua/custom/settings.lua`.
- Preserve Kickstart.nvim updateability: avoid broad refactors, formatting churn, or rewrites of upstream-owned sections.
- Keep verification scoped to the change, and confirm whether any Neovim config files were modified.

## `@@XX` Marker Replacement Requests

- Inspect the current marker implementation in `lua/custom/settings.lua` before changing marker behavior; the existing `@@nl` replacement is the source of truth for local conventions.
- Keep marker replacement logic in `lua/custom/settings.lua` unless it cannot reasonably be reached from the custom module; avoid `init.lua` changes for marker behavior.
- Treat markers such as `@@nl` and future `@@XX` tokens as literal text, not Lua patterns.
- Preserve surrounding text and cursor placement when replacing markers, including intentional typing forms such as `@@nl ` when the implementation supports them.
- Guard against recursive edits, validate the buffer before editing, and skip invalid, non-current, unmodifiable, or readonly buffers.
- Re-check the line before applying scheduled replacement so stale async edits are skipped.
