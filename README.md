# Shelf

A native macOS dashboard for triaging many Terminal.app windows — especially when dozens of them are running Claude Code.

Every Terminal tab becomes a card:

- **Claude sessions** show the session title, an AI "Done / Next" line, your last prompt, tokens, estimated cost,
  prompt count, session length, and a brain that fills up with the context window.
- **Plain shells** show the directory and the running command.
- **Status** — 🟠 Needs you (Claude finished within the last 3h) · 🟢 Working · ⚪ Idle · 🔵 Shell. Cards needing you sort first.

Interactions:

- **Hover** a card to flip it over to a summary of Claude's last response.
- **Click** a card to bring its window forward, sized to the screen. Right-click for more.
- **＋** (top-right on hover) adds notes to a session; the latest shows on the card and notes are searchable.
- **Tile windows** grids the Terminal windows of the cards on screen (respects the filter); click again to restore.
- **⌥⌘T** or the menu bar icon brings the dashboard back.

## Build, run, test

Requires macOS 13+ and the Xcode Command Line Tools (Xcode itself isn't needed).

    make run        # build Shelf.app and open it
    make test       # run the unit tests
    make coverage   # tests + line/region coverage report for Sources/Core
    make icon       # regenerate Resources/AppIcon.icns

On first launch, allow Shelf to control Terminal (System Settings → Privacy & Security → Automation).
`.build/Shelf --dump` prints what the dashboard would show, without the UI.

The project builds with plain `swiftc` via the Makefile: SwiftPM fails on some Command Line Tools installs, and
XCTest ships only with Xcode, so tests use a small built-in harness (`Tests/Support/TestHarness.swift`).

## Layout

```
Sources/Core/    Pure logic, 100% unit-test coverage. System access goes through CommandRunning.
  TerminalClient       AppleScript for Terminal: snapshot tabs, focus, move windows
  ProcessScanner       ps/lsof → what runs on each tty, and where
  ClaudeSessionStore   ~/.claude/sessions + incremental transcript reading
  TranscriptParser     JSONL → titles, prompts, token usage, context fill
  Pricing              per-model cost and context window
  Triage               status rules, sorting, filtering, SessionAssembler
  Summarizer           `claude -p --model haiku` summaries, cached on disk
  WindowLayout         expand/grid math in AppleScript coordinates
  Storage, GitInfo, Formatting
Sources/App/     AppKit/SwiftUI shell: app delegate, DeckStore (state + refresh loop), views
Tests/           One suite per Core file
```

## Data sources

| What | Where |
| --- | --- |
| Windows, tabs, ttys, bounds | Terminal AppleScript |
| Processes and working directories | `ps`, `lsof` |
| Claude session per process, busy/idle | `~/.claude/sessions/<pid>.json` |
| Titles, prompts, replies, token usage | `~/.claude/projects/<cwd-slug>/<session>.jsonl` |
| AI summaries, notes | `~/Library/Application Support/Shelf/` |

Costs are API-equivalent estimates, not what a Claude subscription bills.
