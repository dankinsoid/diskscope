# Design

## Goal

Answer "what is eating my disk, and what of it can I delete?" — not just draw a
tree of sizes. The second half of that question is the reason this tool exists.

## Layers

    DiskKit                      dscope
    ├── Scan      filesystem  →  scan       one-shot output
    ├── Snapshot  tree ⇄ disk    explore    interactive TUI
    ├── Query     search/filter  select      batch operations
    └── Action    trash/delete

`DiskKit` knows nothing about presentation. This split is not academic: scanning
costs minutes while exploring is interactive, so every question the user asks
must be answered from a snapshot rather than by touching the disk again.

The same split is what later allows a SwiftUI app on top of the same core,
the way `cleanup-simulators` shares `SimulatorKit` between its CLI and app.

## Scanning

`getattrlistbulk` returns names and metadata for many entries per syscall. Its
packed layout is decoded by hand — fields appear in ascending bitmap-bit order,
64-bit fields padded to 8 bytes — so tests verify each field against `lstat`.

Sizes are allocated blocks, matching `du`:

- sparse files and compressed files count what they occupy, not their logical size;
- hard links count once per inode, tracked in a shared set of seen inodes;
- directories are visited once per inode as well;
- mount points are not crossed by default, so a scan stays off external and
  network volumes.

That third rule is what makes a scan of `/` correct. macOS firmlinks
`/System/Volumes/Data` onto `/`, so most of the disk is reachable by two paths
— and both report the same device id, which is why staying on one device is not
enough. Measured against a disk holding 384 GB, walking both paths reported
759 GB. The two paths do share an inode, so counting inodes catches what device
ids cannot, and the same rule makes symlink loops harmless.

Not covered by any tree walk, and reported separately: APFS local snapshots.
They routinely hold tens of gigabytes and explain most of the gap between "free
space" in Finder and the sum of a scan.

## Snapshots

A scan is written to disk and reopened later. This gives instant re-filtering,
and makes it possible to diff two scans — "what grew this week" — which is often
a faster route to the culprit than absolute size.

## Selection

Bulk selection is a primary workflow, not a convenience. The shape of it:
match by keyword or regex across the whole snapshot, select every match, then
uncheck the few exceptions. Clearing every `.build` directory except one active
project is the canonical case.

Selection therefore lives on the snapshot, not on the visible rows, and the
running total of "space that would be freed" is always visible.

## Deletion

Move to Trash by default, via `NSWorkspace`, so the system owns undo.
Permanent deletion is available but requires explicit confirmation — the Trash
sits on the same volume and frees nothing until emptied, which matters when the
point of the exercise is reclaiming space.

## Machine-readable output

Every command has a `--json` form alongside its human output, and the TUI is
never required to reach any capability. This is what makes the CLI usable by
agents; an MCP server or a skill is then a thin wrapper over a stable interface
rather than a parallel implementation. Skills are the broader target, since not
every agent runtime supports MCP.

## Knowledge layer — later

Classifying a path as safe-to-delete needs knowledge no static list fully
covers. Planned as a pluggable verdict source rather than a built-in database:

- a verdict is a stored field on a node, tagged by origin (`builtin`, `agent`,
  `user`), with user verdicts winning and surviving rescans;
- verdicts live beside the snapshot, so a rescan does not erase them;
- an agent adapter is a configured command speaking JSON over stdin/stdout,
  receiving only paths and metadata — never file contents — and returning a
  category, a confidence and one line of reasoning.

Keeping the provider configurable puts billing and model choice on the user's
side, and lets a local model serve anyone unwilling to send paths anywhere.
