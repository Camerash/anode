# Repository Workflow

- After completing and verifying any code or configuration change, commit it to
  the current branch. Stage only changes belonging to the completed task, and
  do not amend an existing commit unless the user explicitly requests it.

## Rapid UI Iteration

- Until the user revokes this rule, treat UI work as quick idea iteration.
- Do not run the full Flutter test suite, build for iOS Simulator, or perform
  Simulator UI validation unless the user explicitly requests it.
- Use only lightweight, focused checks when they materially help catch errors;
  the user will manually validate completed iterations.
