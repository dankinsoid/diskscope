---
name: diskscope
description: Find what is using disk space and delete safely with dscope. Use when asked to free up space, find large or stale files, locate build artifacts and caches, or explain why a disk is full.
---

# diskscope

`dscope` reports disk usage and deletes what the user chooses. Every command
takes `--json`; use it, and read the fields rather than parsing the text output.

## Always scan to a snapshot first

`dscope` scans the whole disk by default, which takes a few minutes; a home
directory takes about ten seconds. A snapshot loads in under a second, so scan
once and query it repeatedly:

```bash
dscope scan / --save /tmp/disk.dscope --json > /dev/null
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
| Volumes and snapshots | `dscope volumes --json` |
| Largest entries anywhere | `dscope top <path> --count 20 --json` |
| Large and untouched | `dscope top <path> --stale-days 180 --json` |
| Find by name | `dscope search <query> <path> --mode glob --json` |
| Plan a cleanup | `dscope clean <query> <path> --except <keep> --json` |

Options differ per command — these are not interchangeable:

| Command | Options |
|---|---|
| `scan` | `--depth`, `--min`, `--save`, `--under` |
| `search` | `--mode`, `--min`, `--limit`, `--sort`, `--full-path`, `--include-nested`, `--under` |
| `top` | `--count`, `--files-only`, `--stale-days`, `--under` |
| `clean` | `--mode`, `--min`, `--except`, `--apply`, `--yes`, `--permanent` |

`--under <path>` re-roots a snapshot on a subtree, which is how you look inside
one directory without rescanning or printing the whole disk:

```bash
dscope scan /tmp/disk.dscope --under ~/Library/Developer --depth 2 --json
```

For directory names prefer `--mode glob` with an exact pattern: a substring
search for `.build` also matches `*.build` inside DerivedData, which can differ
by many gigabytes.

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

`clean` always works against the live filesystem, never a snapshot: a saved scan
may be hours old, and deleting from stale paths is how the wrong thing goes. Its
sizes can therefore differ slightly from a snapshot's.

## Reading the results

- `bytes` is allocated size, matching `du`. `humanSize` is the same number
  formatted.
- Nested matches are omitted by default: searching `node_modules` returns the
  outermost copy, so summing `bytes` never double-counts.
- `truncated: true` means `--limit` cut results off; raise it before concluding
  you have seen everything.
- `scan` returns the tree under `tree`; `root` is the path that was scanned, not
  the tree itself. `search` and `top` return `matches`.
- `top` reports places where space accumulates, never an entry inside another
  one, so its sizes can be summed. It deliberately omits directories that merely
  pass their size to a single child.
- `unreadablePaths` lists directories that could not be read. Those sizes are
  lower bounds — mention this rather than presenting the total as exact.

## When the total looks too small

A directory tree cannot contain everything that occupies a disk. Every scan
reports an `accounting` object saying so:

- `measuredBytes` against `volumeUsedBytes` — what the walk reached, against
  what the volume reports in use;
- `unaccountedBytes` — the difference;
- `coversWholeVolume` — false when only a directory was scanned, in which case
  the difference is simply the rest of the disk.

When `coversWholeVolume` is true and `unaccountedBytes` is large, the space is
held by things no tree contains. Run `dscope volumes --json` to see them:

- **other volumes in the same APFS container** — Preboot, VM swap, Recovery and
  the System volume can hold tens of gigabytes between them. They share one
  storage pool, so the volumes in a pool all report the same `usedBytes`; never
  sum them. Nothing here is deletable through this tool.
- **APFS local snapshots**, listed as `localSnapshots`. Remove with
  `tmutil deletelocalsnapshots <name>` — tell the user the command rather than
  running it.
- **unreadable directories**. Check with `dscope access --json`: when
  `fullDiskAccess` is false, give the user the `instructions` field rather than
  trying to grant it yourself. Some directories stay unreadable even with it
  granted, because System Integrity Protection forbids reading them at all —
  `sudo` does not help either.
- **other mounted volumes**, which a scan does not cross into. A scan reports
  them in its stderr notes; `--cross-mounts` includes them, but then firmlinked
  system paths are counted twice, so prefer scanning such a volume directly.

Scanning `/` needs Full Disk Access to be complete, and takes a few minutes.

## Judging what is safe

`dscope` reports facts, not verdicts. Regenerable things — `.build`,
`DerivedData`, `node_modules`, `target`, `__pycache__`, package caches — cost
only rebuild time. Anything else is the user's data: list it and let them
decide. Never delete something because it merely looks like a cache.
