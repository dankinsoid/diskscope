---
name: diskscope
description: Find what is using disk space and delete safely with dscope. Use when asked to free up space, find large or stale files, locate build artifacts and caches, or explain why a disk is full.
---

# diskscope

`dscope` reports disk usage and deletes what the user chooses. Every command
takes `--json`; use it, and read the fields rather than parsing the text output.

## Always scan to a snapshot first

A scan of a home directory takes ~10s and a full disk several minutes. A
snapshot loads in under a second, so scan once and query it repeatedly:

```bash
dscope scan ~ --save /tmp/home.dscope --json > /dev/null
```

Pass the snapshot path wherever a directory would go:

```bash
dscope top /tmp/home.dscope --json --count 20
```

Re-scan only when the user has deleted things and wants updated numbers.

## Commands

| Task | Command |
|---|---|
| Overview of a tree | `dscope scan <path> --depth 2 --min 1GB --json` |
| Largest entries anywhere | `dscope top <path> --count 20 --json` |
| Large and untouched | `dscope top <path> --stale-days 180 --json` |
| Find by name | `dscope search <query> <path> --mode glob --json` |
| Plan a cleanup | `dscope clean <query> <path> --except <keep> --json` |

Useful options: `--mode substring|glob|regex`, `--min 500MB`, `--limit`,
`--sort size|name|files|modified|accessed`, `--files-only`.

## Deleting

`clean` prints a plan and changes nothing unless `--apply` is given. In a
non-interactive session `--apply` also requires `--yes`, since no one can answer
the prompt.

**Never pass `--apply` unless the user has seen the specific paths and agreed to
them.** Show the dry run first:

```bash
dscope clean '.build' ~/Code --mode glob --min 500MB --json
```

Then, after the user confirms, with any exceptions they named:

```bash
dscope clean '.build' ~/Code --mode glob --min 500MB --except project-a --apply --yes --json
```

`--except` keeps matches whose path contains the given text; repeat it for
several. Deletion moves items to the Trash, so it is recoverable — do not pass
`--permanent` unless the user explicitly asks for it.

## Reading the results

- `bytes` is allocated size, matching `du`. `humanSize` is the same number
  formatted.
- Nested matches are omitted by default: searching `node_modules` returns the
  outermost copy, so summing `bytes` never double-counts.
- `truncated: true` means `--limit` cut results off; raise it before concluding
  you have seen everything.
- `unreadablePaths` lists directories that could not be read. Those sizes are
  lower bounds — mention this rather than presenting the total as exact.

## What the numbers do not include

APFS local snapshots hold tens of gigabytes and appear in no directory tree.
When a scan's total is far below the space actually used, check them:

```bash
tmutil listlocalsnapshots /
```

Scanning `/` needs Full Disk Access for the terminal, and takes several minutes.
Prefer scanning `~` unless the user asks about the whole disk.

## Judging what is safe

`dscope` reports facts, not verdicts. Regenerable things — `.build`,
`DerivedData`, `node_modules`, `target`, `__pycache__`, package caches — cost
only rebuild time. Anything else is the user's data: list it and let them
decide. Never delete something because it merely looks like a cache.
