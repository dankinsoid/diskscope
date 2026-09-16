# diskscope

Find what is eating your disk space.

`dscope` scans a directory tree once, then lets you explore the result: navigate,
search, filter and sort to work out what is safe to delete.

> Status: early development.

## Why another disk usage tool

Drawing a tree of sizes is the easy part. The hard question is *"can I delete
this?"* — `dscope` is built around answering it:

- **Scan once, explore many times.** The tree is saved as a snapshot, so
  filtering and re-sorting never rescans the disk.
- **Search and bulk selection.** Match by keyword or regex, select everything
  that matches, then uncheck the exceptions — the usual way you clear out every
  `.build` directory but one.
- **Facts that inform the decision.** Last access time, file counts, and whether
  a directory is backed by a git remote.

## Requirements

macOS 14.0+

## License

MIT
