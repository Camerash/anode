# Repository Workflow

- After completing and verifying any code or configuration change, commit it to
  the current branch. Stage only changes belonging to the completed task, and
  do not amend an existing commit unless the user explicitly requests it.

## Current - Prototyping phase
- Do not preserve backward compatibility. Remove obsolete paths instead of adding compatibility layers, fallbacks, or migrations.
- Choose the simplest implementation that fully meets the current requirements. Avoid speculative abstractions, configuration, and indirection.
- Grow the system in layers. Start from the smallest version that works end to end, and add each new capability on top of a product that already works. Never trade a working product for unfinished complexity.
- Keep components modular and concerns clearly separated.
- Prefer established, well-maintained libraries when they reduce overall complexity or improve reliability. Do not reimplement common functionality without a clear reason.
- Lean on the dependencies already in the project before writing your own implementation or adding packages. Do not assume a library lacks a capability without checking its documentation and types.
- Make architectural decisions for the long term. Do not accept a stopgap that only works for now and is meant to be replaced later.

## Rapid UI Iteration

- Until the user revokes this rule, treat UI work as quick idea iteration.
- Do not run the full Flutter test suite, build for iOS Simulator, or perform
  Simulator UI validation unless the user explicitly requests it.
- Use only lightweight, focused checks when they materially help catch errors;
  the user will manually validate completed iterations.
