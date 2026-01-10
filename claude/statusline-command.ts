#!/usr/bin/env bun

import { $ } from "bun";

// Catppuccin colors (256-color mode)
const colors = {
  branch: "\x1b[38;5;111m", // blue
  added: "\x1b[38;5;151m", // green
  removed: "\x1b[38;5;211m", // pink
  model: "\x1b[38;5;183m", // mauve
  tokens: "\x1b[38;5;216m", // peach
  reset: "\x1b[0m",
};

interface ToolUseResult {
  filePath?: string;
  originalFile?: string;
  content?: string;
}

interface TranscriptEntry {
  toolUseResult?: ToolUseResult;
}

interface Input {
  cwd: string;
  transcript_path: string;
  model: { id: string; display_name: string };
  context_window: {
    current_usage: {
      input_tokens: number;
      cache_creation_input_tokens: number;
      cache_read_input_tokens: number;
    };
    context_window_size: number;
  };
}

async function calculateNetDiff(
  transcriptPath: string
): Promise<{ added: number; removed: number }> {
  const file = Bun.file(transcriptPath);
  if (!(await file.exists())) {
    return { added: 0, removed: 0 };
  }

  const text = await file.text();
  const lines = text.trim().split("\n");

  const fileOriginals = new Map<string, string>();

  for (const line of lines) {
    try {
      const entry: TranscriptEntry = JSON.parse(line);
      const result = entry.toolUseResult;

      if (typeof result !== "object" || !result?.filePath) continue;
      if (!result.originalFile && !result.content) continue;

      // Only save first occurrence (original state before any edits)
      if (!fileOriginals.has(result.filePath)) {
        fileOriginals.set(result.filePath, result.originalFile ?? "");
      }
    } catch {}
  }

  let added = 0,
    removed = 0;

  // Create temp dir for diff comparison
  const tmpDir = await $`mktemp -d`.text().then((s) => s.trim());

  for (const [filePath, original] of fileOriginals) {
    try {
      const currentFile = Bun.file(filePath);
      if (await currentFile.exists()) {
        // Write original to temp file
        const tmpOriginal = `${tmpDir}/original`;
        await Bun.write(tmpOriginal, original);

        const diff = await computeDiff(tmpOriginal, filePath);
        added += diff.added;
        removed += diff.removed;
      } else {
        // File deleted - count original lines as removed
        removed += original.split("\n").filter((l) => l).length;
      }
    } catch {}
  }

  // Cleanup
  await $`rm -rf ${tmpDir}`.quiet();

  return { added, removed };
}

async function computeDiff(
  originalFile: string,
  currentFile: string
): Promise<{ added: number; removed: number }> {
  // Use actual diff command for accurate results
  const result = await $`diff ${originalFile} ${currentFile} 2>/dev/null || true`.text();

  let added = 0,
    removed = 0;

  for (const line of result.split("\n")) {
    if (line.startsWith(">")) added++;
    if (line.startsWith("<")) removed++;
  }

  return { added, removed };
}

function getTokenInfo(input: Input): string {
  const size = input.context_window?.context_window_size;
  if (!size) return "";

  const usage = input.context_window?.current_usage;
  const current = usage
    ? usage.input_tokens +
      usage.cache_creation_input_tokens +
      usage.cache_read_input_tokens
    : 0;
  const pct = Math.floor((current * 100) / size);

  const filled = Math.floor(pct / 20);
  const bar = "\u25B0".repeat(filled) + "\u25B1".repeat(5 - filled);

  const currentK = Math.floor(current / 1000);
  const sizeK = Math.floor(size / 1000);

  return `${colors.tokens}${bar} ${currentK}k/${sizeK}k tokens${colors.reset}`;
}

async function main() {
  const input: Input = await Bun.stdin.json();

  // Get git branch
  const cwd = input.cwd;
  const gitBranch = await $`git -C ${cwd} branch --show-current 2>/dev/null || echo "no-git"`
    .text()
    .then((s) => s.trim());

  // Get model name
  const modelName = input.model.display_name;

  // Calculate net diff
  const { added, removed } = await calculateNetDiff(input.transcript_path);

  // Get token info
  const tokenInfo = getTokenInfo(input);

  // Output with ANSI colors
  console.log(
    `${colors.branch}${gitBranch}${colors.reset} | ` +
      `${colors.added}+${added}${colors.reset} ${colors.removed}-${removed}${colors.reset} | ` +
      `${colors.model}${modelName}${colors.reset} | ` +
      tokenInfo
  );
}

main().catch(() => process.exit(1));
