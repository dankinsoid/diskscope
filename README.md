# diskscope

Find what is eating your disk space.

`dscope` scans a directory once, saves the result, and then answers questions
about it instantly — what is large, what is stale, and what can go.

> Status: early development. The interactive interface is not built yet; every
> capability is available from the command line.

## Why another disk usage tool

Drawing a tree of sizes is the easy part. The hard question is *"can I delete
this?"*, and that is what the tool is shaped around.

- **Scan once, ask many times.** A snapshot of 1.4M entries loads in 0.3s,
  against 10s to rescan. Filtering and sorting never touch the disk again.
- **Search and bulk delete with exceptions.** Match by name, glob or regex,
  then keep the ones still in use.
- **Facts that inform the decision.** Last access time, file counts, and sizes
  that agree with `du` exactly.
- **Scriptable.** Every command takes `--json`, so agents and scripts use the
  same capabilities as a human.

## Usage

Scan a directory and show the top two levels, hiding anything under 1 GB:

```console
$ dscope scan ~ --depth 2 --min 1GB
64.0 GB	/Users/you
25.9 GB	├── Code/
12.7 GB	│   ├── project-a/
 6.8 GB	│   └── project-b/
 8.1 GB	└── Library/
```

Save a snapshot, then explore it without rescanning:

```console
$ dscope scan ~ --save ~/home.dscope
$ dscope search '.build' ~/home.dscope --mode glob --min 500MB
5.8 GB	/Users/you/Code/project-a/.build
2.6 GB	/Users/you/Code/project-b/.build
```

Find large things you have not touched in half a year:

```console
$ dscope top ~/home.dscope --stale-days 180
5.8 GB	/Users/you/Code/project-a/.git/lfs  last used 11mo ago
1.1 GB	/Users/you/Code/experiments/old     last used 7mo ago
```

Delete every match except the projects still in use. Without `--apply` this
only prints the plan:

```console
$ dscope clean '.build' ~/Code --except project-a --min 500MB
5.8 GB	/Users/you/Code/project-b/.build
1.2 GB	/Users/you/Code/project-c/.build
kept    	/Users/you/Code/project-a/.build
would free 7.0 GB from 2 entries — re-run with --apply
```

Items move to the Trash, so a mistake is recoverable. `--permanent` skips it.

### Machine-readable output

```console
$ dscope search node_modules ~/home.dscope --json --limit 1
{"humanSize":"1.1 GB","matchCount":1,"matches":[{"bytes":1229438976, ...}]}
```

Nested matches are skipped by default: searching for `node_modules` reports the
outermost copy, never the same bytes twice.

## How sizes are counted

Sizes match `du` exactly — allocated blocks, not logical size, so sparse and
compressed files report what they actually occupy. Hard links count once.
Mount points are not crossed unless you ask, since the macOS data volume is
firmlinked into `/` and crossing counts everything twice.

Not visible to any tree walk: APFS local snapshots, which routinely hold tens
of gigabytes. Check them with `tmutil listlocalsnapshots /`.

Some directories need Full Disk Access to read. Without it they are reported as
unreadable rather than silently counted as empty.

## Building

```console
$ swift build -c release
$ ./.build/release/dscope --help
```

## Requirements

macOS 14.0+

## License

MIT
