# Claude Code Statusline - Bun Rewrite Plan

## Current State

The statusline is implemented in bash (`claude/statusline-command.sh`) and shows:
- Git branch (blue)
- Net lines changed: `+X -Y` (green/pink) - GitHub-style net diff
- Model name (purple)
- Token usage with progress bar (peach)

**Theme:** Catppuccin colors (256-color mode)

## Performance Issue

Current: ~1 second execution time

Bottleneck: Multiple subprocess forks for `jq`, `diff`, `grep`, `md5sum`

## Rewrite Goal

Rewrite in Bun/TypeScript for ~100-200ms execution time.

## How It Works

### Input
Script receives JSON via stdin with:
```json
{
  "cwd": "/path/to/project",
  "transcript_path": "/root/.claude/projects/.../session.jsonl",
  "model": { "id": "claude-opus-4-5-...", "display_name": "Opus 4.5" },
  "context_window": {
    "current_usage": { "input_tokens": N, "cache_creation_input_tokens": N, "cache_read_input_tokens": N },
    "context_window_size": 200000
  }
}
```

### Net Diff Logic
1. Parse transcript JSONL file
2. Find all `toolUseResult` entries with `filePath` and (`originalFile` OR `content`)
3. For each unique file, save the FIRST `originalFile` (or empty string for new files)
4. Compare original state to current file on disk using diff
5. Sum up net additions/removals across all files

### Output
ANSI-colored string:
```
main | +78 -30 | Opus 4.5 | ▱▱▱▱▱ 25k/200k tokens
```

## Implementation Steps

### 1. Create Bun script
File: `claude/statusline-command.ts`

```typescript
#!/usr/bin/env bun

import { $ } from "bun";

// Read JSON from stdin
const input = await Bun.stdin.json();

// Get git branch
const cwd = input.cwd;
const gitBranch = await $`cd ${cwd} && git branch --show-current 2>/dev/null || echo "no-git"`.text().then(s => s.trim());

// Get model name
const modelName = input.model.display_name;

// Parse transcript for net diff
const transcriptPath = input.transcript_path;
// ... (see full logic below)

// Calculate token usage
// ...

// Output with ANSI colors
console.log(`\x1b[38;5;111m${gitBranch}\x1b[0m | ...`);
```

### 2. Net Diff Implementation

```typescript
interface ToolUseResult {
  filePath?: string;
  originalFile?: string;
  content?: string;
}

async function calculateNetDiff(transcriptPath: string): Promise<{added: number, removed: number}> {
  const file = Bun.file(transcriptPath);
  const text = await file.text();
  const lines = text.trim().split('\n');

  const fileOriginals = new Map<string, string>();

  for (const line of lines) {
    try {
      const entry = JSON.parse(line);
      const result = entry.toolUseResult;

      if (typeof result !== 'object' || !result?.filePath) continue;
      if (!result.originalFile && !result.content) continue;

      // Only save first occurrence
      if (!fileOriginals.has(result.filePath)) {
        fileOriginals.set(result.filePath, result.originalFile ?? '');
      }
    } catch {}
  }

  let added = 0, removed = 0;

  for (const [filePath, original] of fileOriginals) {
    try {
      const currentFile = Bun.file(filePath);
      if (await currentFile.exists()) {
        const current = await currentFile.text();
        const diff = computeDiff(original, current);
        added += diff.added;
        removed += diff.removed;
      } else {
        // File deleted - count original lines as removed
        removed += original.split('\n').filter(l => l).length;
      }
    } catch {}
  }

  return { added, removed };
}

function computeDiff(original: string, current: string): {added: number, removed: number} {
  const origLines = new Set(original.split('\n'));
  const currLines = new Set(current.split('\n'));

  // Simple line-based diff (can use proper diff library for accuracy)
  let added = 0, removed = 0;

  for (const line of currLines) {
    if (!origLines.has(line)) added++;
  }
  for (const line of origLines) {
    if (!currLines.has(line)) removed++;
  }

  return { added, removed };
}
```

### 3. Token Usage

```typescript
function getTokenInfo(input: any): string {
  const usage = input.context_window?.current_usage;
  if (!usage) return '';

  const current = usage.input_tokens + usage.cache_creation_input_tokens + usage.cache_read_input_tokens;
  const size = input.context_window.context_window_size;
  const pct = Math.floor((current * 100) / size);

  const filled = Math.floor(pct / 20);
  const bar = '▰'.repeat(filled) + '▱'.repeat(5 - filled);

  const currentK = Math.floor(current / 1000);
  const sizeK = Math.floor(size / 1000);

  return `\x1b[38;5;216m${bar} ${currentK}k/${sizeK}k tokens\x1b[0m`;
}
```

### 4. Color Constants (Catppuccin)

```typescript
const colors = {
  branch: '\x1b[38;5;111m',    // blue
  added: '\x1b[38;5;151m',     // green
  removed: '\x1b[38;5;211m',   // pink
  model: '\x1b[38;5;183m',     // mauve
  tokens: '\x1b[38;5;216m',    // peach
  reset: '\x1b[0m'
};
```

### 5. Update install.sh

```bash
# Check if bun is available, fallback to bash script
if command -v bun &> /dev/null; then
  cp "$SCRIPT_DIR/claude/statusline-command.ts" ~/.claude/
  chmod +x ~/.claude/statusline-command.ts
  # Update settings to use .ts version
else
  cp "$SCRIPT_DIR/claude/statusline-command.sh" ~/.claude/
  chmod +x ~/.claude/statusline-command.sh
fi
```

### 6. Update settings.json

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline-command.ts"
  }
}
```

## Testing

```bash
# Test with sample input
echo '{"cwd":"/root/solostream","transcript_path":"/root/.claude/projects/-root-solostream/SESSION.jsonl","model":{"id":"opus","display_name":"Opus 4.5"},"context_window":{"current_usage":{"input_tokens":1000,"cache_creation_input_tokens":0,"cache_read_input_tokens":0},"context_window_size":200000}}' | time bun claude/statusline-command.ts
```

## Notes

- Use `Bun.file()` for fast file reading
- Use `Bun.stdin.json()` for stdin parsing
- For accurate diff, consider using a proper diff algorithm or `diff` command via `$``
- The bash version remains as fallback for systems without Bun
