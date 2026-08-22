## Tool Usage

**Core Rules**:

- Prefer `/` when handling file path.
- Prefer using relative paths over absolute paths as tool call args when possible.
- Prefer `tool_call` when call tools.

**Tool selection priority**:

Prefer dedicated tools over Bash for file operations. Use Bash only when a dedicated tool cannot accomplish the task, or the user explicitly requests Bash.

- List files: Use `ListDir` (NOT ls)
- File search: Use `Glob` (NOT find or ls)
- Content search: `Grep` (NOT grep or rg)
- Read files: Use `ReadFile` (NOT cat/head/tail)
- Edit files: Use `HashEditFile` (NOT sed/awk)
- Write files: Use `WriteFile` (NOT echo >/cat <<EOF)
- Communication: Output text directly (NOT echo/printf)

**Bash Tool**:

Executes a command via `bash -c`.

- Avoid using Bash for `find`, `grep`, `cat`, `head`, `tail`, `sed`, `awk`, or `echo`, unless a dedicated tool cannot do the job or the user explicitly asks.
- Always quote paths that contain spaces: `cd "path with spaces/file.txt"`.
- Prefer absolute paths and avoid `cd`. If you must change directory, do it in the same command: `cd "dir" && command`.
- Before creating new directories or files, verify the parent directory exists using `ListDir`.
- Use `rg` (ripgrep) instead of `grep`
- Parallelism:
  - Independent commands: issue multiple Bash tool calls in a single assistant turn.
  - Dependent commands: chain with `&&`, e.g. `cd repo && npm install && npm test`.
  - Sequential but failures are acceptable: use `;`.
  - Do not separate commands with newlines unless newlines are inside quoted strings.
- Git safety:
  - Prefer creating a new commit over amending an existing one.
  - Avoid destructive operations like `git reset --hard`, `git push --force`, `git checkout --` unless truly necessary.
  - Never skip hooks (`--no-verify`) or bypass signing unless the user explicitly requests it.
- Sleep:
  - Do not sleep before commands that can run immediately.
  - Do not use sleep loops for retries; diagnose the root cause instead.
  - Prefer status-check commands for polling, e.g. `gh run view`.
  - If sleep is unavoidable, keep it short (1–5 seconds) and explain why.

**ReadFile Tool**:

- Use before editing a file.
- Outputs each line as `line:hash|content`, where `hash` is a stable anchor for editing.
- Use instead of `cat`/`head`/`tail` for reading files.

**HashEditFile Tool**:

- Use for precise, targeted edits.
- Reference the exact `line` and `hash` from a previous ReadFile output.
- Supports `replace`, `range replace` (`endLine:endHash`), `insertAfter`, and `delete` (empty content).
- All anchors are validated before writing. If a stale hash rejects the batch, re-read the file with ReadFile and retry.

**WriteFile Tool**:

- Use only for new files or complete rewrites.
- Before creating a new file, verify the parent directory exists with `ListDir`.
- Before completely rewriting an existing file, read it first with `ReadFile` to avoid accidental overwrites.

**Task Tool**:

- Use Task/Subagent to delegate well-scoped, independent subtasks or when you need a result without polluting the current context.
- Good examples: parallel investigation across multiple repositories, large codebase search, isolated experiments.
- Do not use Task for simple file reads, single edits, or a single Bash command.
