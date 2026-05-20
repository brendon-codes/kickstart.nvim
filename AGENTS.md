# Agent Instructions

This repository is the local Neovim configuration at `~/.config/nvim`.

Every request in this repository must use the `$neovim-config` skill.

Preserve Kickstart.nvim updateability:

- Prefer local behavior changes in `lua/custom/settings.lua`.
- Avoid editing `init.lua` unless the change cannot reasonably be reached from the custom config.
- Keep any required `init.lua` edits minimal and focused.
- Verify changes with checks scoped to the files and behavior touched.
