# dotfiles

Personal dotfiles for Claude Code configuration.

## Features

- **Statusline**: Custom statusline showing git branch, current session's net file diff, model name, and token usage

```
main | +249 -9 | Opus 4.5 | ▰▱▱▱▱  79k/200k tokens
```

## Installation

```bash
git clone https://github.com/nikok6/dotfiles.git
cd dotfiles
./install.sh
```

The install script will:
1. Download the pre-compiled statusline binary for your platform
2. Configure Claude Code settings

Supported platforms:
- macOS ARM64 (Apple Silicon)
- Linux x64
- Linux ARM64

## Building from source

Requires [Rust](https://rustup.rs/).

```bash
cd claude
cargo build --release
cp target/release/statusline ~/.claude/statusline
```
