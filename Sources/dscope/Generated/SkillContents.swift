// Generated from skills/diskscope/SKILL.md by Scripts/embed-skill.sh
// Edit that file, not this one.

extension Skill {

    /// The skill text, embedded so an installed binary carries it.
    static let contents = """
---
name: diskscope
description: Find what is using disk space and delete safely with dscope. Use when asked to free up space, find large or stale files, locate build artifacts and caches, or explain why a disk is full.
---

# diskscope

`dscope` measures disk usage and deletes what the user chooses. Every command
takes `--json`; use it and read the fields rather than parsing text.

Always name the command — `dscope scan`, `dscope search`. A bare `dscope`, or
`dscope <path>`, opens an interactive browser when stdout is a terminal, which
is not what you want from a tool call.

## Scan once, then query the snapshot

**Scan with `--save` at the start of the conversation and use that snapshot for
every question afterwards.** A scan is the expensive part — minutes for a whole
disk, about ten seconds for a home directory — and repeating it per question
wastes the user's time on an answer that has not changed.

```bash
# once, at the start
dscope scan / --save /tmp/dscope-session.dscope --json > /dev/null
```

Keep that path for the rest of the session. Only scan again when the user has
deleted something and wants updated figures, and prefer `update` even then.
If the user asks about a directory you have already covered, use `--under`
rather than scanning it separately.

A positional path is always **scanned**. A saved scan is passed as
`--snapshot` (`-S`), and every command accepts it — this is how nearly every
call in a session should look:

```bash
dscope top --snapshot /tmp/dscope-session.dscope --count 20 --json
dscope search --snapshot /tmp/dscope-session.dscope --name .build --glob --json
dscope scan --snapshot /tmp/dscope-session.dscope --depth 2 --json
```

Reading a snapshot costs about a second and happens on every command, so prefer
a few broad queries to many narrow ones.

Refresh with `update` rather than scanning again — it asks the filesystem which
paths changed and re-measures only those:

```bash
dscope update /tmp/dscope-session.dscope --json
```

`rescannedDirectories` and `deltaBytes` say what moved. `fullScanReason` is set
when the change journal could not answer and everything was re-measured anyway,
which is expected for a snapshot more than a few days old.

## Conditions

`search`, `top` and `clean` share one set of conditions, and they combine — each
narrows the result further, as find(1) predicates do.

| Condition | Meaning |
|---|---|
| `--name <pattern>` (`-n`) | substring of the name; add `--glob`, `--regex` or `--path` |
| `--name 'build/'` | trailing slash means directories only |
| `--size +1GB` / `--size 'over 1GB'` | at least that big |
| `--size 'under 100MB'` | at most that big |
| `--accessed '+6m'` / `--accessed 'over 6m'` | not read for six months |
| `--modified 'within 7d'` | written in the last week |
| `--files-only` / `--dirs-only` | one kind only |
| `--unreadable` | only entries that could not be read |

Time units are `h d w m y`. Repeat `--size` or `--accessed` to bound both ends.

Two things that will otherwise cost you a failed call:

- **A leading dash is read as a flag.** Write `--modified 'within 7d'`, or
  `--modified=-7d`. A bare `--modified -7d` fails with "Missing value".
- **For directory names use `--glob`.** A substring match for `.build` also
  matches `*.build` inside DerivedData; on one machine that was 31.6 GB against
  20.9 GB for the same intent. Writing `--name 'build/'` is the shorthand for
  "the directory called build".

Matching is substring by default — not a regular expression, and not a glob.
`--glob` anchors the pattern to the whole name (`*.log`, `node_modules`), and
`--regex` takes a regular expression.

Per-command options:

| Command | Options |
|---|---|
| `scan` | `--depth`, `--min`, `--save`, `--under` |
| `search` | `--limit`, `--sort`, `--include-nested`, `--under` |
| `top` | `--count`, `--stale-days`, `--under` |
| `clean` | `--except`, `--apply`, `--yes`, `--permanent` |
| `update` | `--output`, `--verbose` |

`--under <path>` re-roots a snapshot on a subtree, which is how to look inside
one directory without rescanning or printing the whole disk:

```bash
dscope scan --snapshot /tmp/dscope-session.dscope --under ~/Library/Developer --depth 2 --json
```

## Worked examples

```bash
# Where the space is
dscope scan --snapshot /tmp/dscope-session.dscope --depth 2 --min 1GB --json

# Biggest things anywhere, none nested inside another
dscope top --snapshot /tmp/dscope-session.dscope --count 20 --json

# Large and long forgotten
dscope search --snapshot /tmp/dscope-session.dscope --size +1GB --accessed 'over 6m' --json

# Build output over half a gigabyte
dscope search --snapshot /tmp/dscope-session.dscope --name .build --glob --size +500MB --json

# Recently grown directories
dscope top --snapshot /tmp/dscope-session.dscope --dirs-only --modified 'within 7d' --json

# What is holding space that no directory tree contains
dscope volumes --json
```

## Deleting

`clean` prints a plan and changes nothing without `--apply`. Non-interactively
`--apply` also needs `--yes`, since nobody can answer the prompt.

**Never pass `--apply` until the user has seen the specific paths and agreed.**

```bash
# 1. the plan
dscope clean '.build' ~/Code --glob --size +500MB --json

# 2. after the user confirms, keeping anything they named
dscope clean '.build' ~/Code --glob --size +500MB --except project-a --apply --yes --json
```

`--except` keeps matches whose path contains the text; repeat for several.
Deletion moves items to the Trash, so it is recoverable — pass `--permanent`
only when the user explicitly asks.

`clean` accepts `--snapshot` for planning, but deletion always works against the
live filesystem: paths are re-checked and anything already gone is reported
rather than assumed. Sizes from a snapshot may therefore differ slightly from
what is freed.

## Reading the results

- `bytes` is allocated size, matching `du`; `humanSize` is the same number
  formatted.
- Nested matches are omitted by default, so summing `bytes` never double-counts.
  `--include-nested` turns that off, and then sums are meaningless.
- `truncated: true` means `--limit` cut the results off.
- `scan` returns the tree under `tree`; `root` is the path scanned, not the
  tree. `search` and `top` return `matches`.
- `top` reports where space accumulates, never an entry inside another, so its
  sizes can be summed. It omits directories that merely pass their size to one
  child.
- `unreadableCount` and a sample in `unreadablePaths`: those sizes are lower
  bounds, so say so rather than presenting a total as exact.

## When the total looks too small

A directory tree cannot contain everything occupying a disk. Every scan reports
an `accounting` object:

- `measuredBytes` against `volumeUsedBytes` — what the walk reached against what
  the volume reports in use;
- `unaccountedBytes` — the difference;
- `coversWholeVolume` — false when only a directory was scanned, where the
  difference is simply the rest of the disk.

When `coversWholeVolume` is true and `unaccountedBytes` is large, run
`dscope volumes --json`. What turns up there:

- **Other volumes of the same APFS container** — Preboot, VM swap, Recovery and
  the System volume held 53 GB between them on one machine, none of it reachable
  from `/`. They share a storage pool, so every volume in one reports the same
  `usedBytes`: never sum them. None is deletable through this tool.
- **Mounted disk images**, marked with `diskImageOf`. Their bytes are the file
  named there, already counted by a scan covering it — do not add them.
- **APFS local snapshots** in `localSnapshots`. Removed with
  `tmutil deletelocalsnapshots <name>`; give the user the command rather than
  running it.
- **Unreadable directories.** Check `dscope access --json`: when
  `fullDiskAccess` is false, pass on the `instructions` field. Some directories
  stay unreadable even with it granted, because System Integrity Protection
  forbids reading them at all — `sudo` does not help either.

Scanning `/` takes a few minutes and needs Full Disk Access to be complete.

`/` is one volume, not the whole machine: an external disk mounted under
`/Volumes` is never reached from it. `--all-volumes` scans each mounted volume
and gathers them under one root, skipping disk images — whose bytes are the file
backing them, already counted — and representing volumes that share a storage
pool once.

```bash
dscope scan --all-volumes --save /tmp/dscope-session.dscope --json > /dev/null
```

## Judging what is safe

`dscope` reports facts, not verdicts. Regenerable things — `.build`,
`DerivedData`, `node_modules`, `target`, `__pycache__`, package caches — cost
only rebuild time. Everything else is the user's data: list it and let them
decide. Never delete something because it merely looks like a cache.
"""
}
