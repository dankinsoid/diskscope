# diskscope

Find what is eating your disk space.

`dscope` scans a directory once, saves the result, and then answers questions
about it instantly — what is large, what is stale, and what can go.

> Status: early development.

## Why another disk usage tool

Drawing a tree of sizes is the easy part. The hard question is *"can I delete
this?"*, and that is what the tool is shaped around.

- **Scan once, ask many times.** A whole disk — 5M entries — scans in about
  three minutes and saves to a 348MB snapshot. Reopening it takes under a
  second, so filtering and sorting never touch the disk again.
- **Search and bulk delete with exceptions.** Match by name, glob or regex,
  then keep the ones still in use.
- **Facts that inform the decision.** Last access time, file counts, and sizes
  that agree with `du` exactly.
- **Scriptable.** Every command takes `--json`, so agents and scripts use the
  same capabilities as a human.

## Usage

Run it with no arguments to scan your home directory and explore the result:

```console
$ dscope
```

Or point it at a directory or a saved snapshot:

```console
$ dscope ~/Code
$ dscope ~/home.dscope
```

Arrow keys or `hjkl` move, `→` enters a directory, `←` goes back. `/` searches
the whole tree, `space` marks an entry and `a` marks everything currently
listed. `d` moves what is marked to the Trash. Marking every search result and
then unmarking the exceptions is the quickest way to clear out, say, every
`.build` directory but one — the running total of what would be freed stays on
screen.

### One-shot commands

Scan the whole disk — the default — showing the top level and hiding anything
under 1 GB:

```console
$ dscope scan --depth 1 --min 1GB
387 GB	/
256 GB	├── Users/
37.1 GB	├── System/
31.4 GB	├── private/
25.5 GB	├── Library/
 7.2 GB	└── (24 smaller entries)
measured 387 GB of 467 GB in use — 80.4 GB is not in any directory tree
run 'dscope volumes' to see the volumes and APFS snapshots holding it
```

Entries below the threshold are grouped rather than dropped, so what is shown
still adds up to its parent. Scanning one directory instead reports its share
of the disk:

```console
$ dscope scan ~/Code --depth 1 --min 10GB
59.6 GB	/Users/you/Code
24.1 GB	├── project-a/
11.8 GB	├── project-b/
23.7 GB	└── (93 smaller entries)
this is 14% of the 434 GB in use on /System/Volumes/Data; 374 GB is elsewhere
```

Refresh a snapshot without rescanning the disk — the filesystem is asked what
changed, and only that is re-measured:

```console
$ dscope update ~/home.dscope
re-measured 2 directories in 0.0s, +250 MB
60.1 GB	/Users/you/Code
```

Conditions combine, in the manner of `find`:

```console
$ dscope search ~/home.dscope --name .build --glob --size +500MB
$ dscope search ~/home.dscope --size +1GB --accessed 'over 6m'
$ dscope top ~/home.dscope --dirs-only --modified 'within 7d'
```

`--size` and `--accessed` take `+N` for "at least" and `-N` for "at most", or
the words `over`, `under` and `within` where a leading dash would be read as a
flag. Time units are `h d w m y`.

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

A directory whose name begins with a dot — `.build`, `.gradle` — keeps that name
in the Trash, and the Finder hides dotfiles: the Trash can look empty when it is
not. Press Cmd-Shift-. there, or check with `ls -a ~/.Trash`.

### Machine-readable output

```console
$ dscope search node_modules ~/home.dscope --json --limit 1
{"humanSize":"1.1 GB","matchCount":1,"matches":[{"bytes":1229438976, ...}]}
```

Nested matches are skipped by default: searching for `node_modules` reports the
outermost copy, never the same bytes twice.

### Every disk, not just the boot volume

`/` is one volume. An external disk, or anything else mounted elsewhere, is
never reached by walking it:

```console
$ dscope scan --all-volumes --depth 1
```

Each mounted volume is scanned and gathered under one root. Disk images are
skipped — their bytes are the file backing them, which the scan already counted
— and volumes sharing a storage pool are represented once.

### Space no directory tree contains

A tree walk cannot find everything that fills a disk. `dscope volumes` shows
what else is holding space — other volumes in the same APFS container, and
local snapshots:

```console
$ dscope volumes
disk3  435 GB used of 460 GB, 25.5 GB free
    /  ro
    /System/Volumes/Data
    /System/Volumes/Preboot
    /System/Volumes/VM

3 local APFS snapshots — these hold space that no directory tree shows:
  com.apple.os.update-2C083E7D042E96779F886D9092C61E88A0E7AB9EE4C8ACE14FD9C26E43B17C55
Remove with: tmutil deletelocalsnapshots <name>
```

Volumes in one container share a storage pool, so they all report the same used
figure — do not add them up. On one machine the Preboot and VM volumes held
53 GB between them, none of it visible from `/`.

## How sizes are counted

Sizes match `du` exactly — allocated blocks, not logical size, so sparse and
compressed files report what they actually occupy. Hard links count once.
Mount points are not crossed unless you ask, since the macOS data volume is
firmlinked into `/` and crossing counts everything twice.

Not visible to any tree walk: APFS local snapshots, which routinely hold tens
of gigabytes. Check them with `tmutil listlocalsnapshots /`.

Some directories need Full Disk Access to read. Without it they are reported as
unreadable rather than silently counted as empty.

## Install

Homebrew:

```console
$ brew tap dankinsoid/diskscope https://github.com/dankinsoid/diskscope
$ brew install dscope
```

[mise](https://mise.jdx.dev):

```console
$ mise use -g spm:dankinsoid/diskscope
```

Or build it yourself:

```console
$ swift build -c release
$ cp .build/release/dscope /usr/local/bin/
```

`DiskKit`, the library underneath, is a Swift package in its own right:

```swift
.package(url: "https://github.com/dankinsoid/diskscope", from: "1.0.0")
```

## Teaching an assistant to use it

```console
$ dscope skill
installed to ~/.claude/skills/diskscope/SKILL.md
```

This writes a skill describing the commands, the JSON they return, and the
traps worth knowing — scan once and keep the snapshot, what a trailing slash
means, why a mounted disk image must not be added to a total. Use `--to` for
an assistant that looks elsewhere, or `--print` to read it first.

## Requirements

macOS 14.0 or newer. Scanning `/` needs Full Disk Access to be complete —
`dscope access` says whether it is granted.

## License

MIT
