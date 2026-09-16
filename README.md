# diskscope

Find what is eating your disk space.

`dscope` scans once, saves the result, and then answers questions about it
instantly — what is large, what is stale, and what can safely go. Use it from a
terminal, or hand it to a coding agent and ask in plain language.

```console
$ dscope scan / --save ~/disk.dscope
⠸ ━━━━──────── 141 GB / 382 GB  1.4M files  …/PrivateHeaders/src/core/util

$ dscope search --snapshot ~/disk.dscope --name .build --glob --size +500MB
5.8 GB	/Users/you/Code/project-a/.build
4.2 GB	/Users/you/Code/project-b/.build
2.6 GB	/Users/you/Code/project-c/.build
```

## Install

```console
$ brew tap dankinsoid/diskscope https://github.com/dankinsoid/diskscope
$ brew install dscope
```

Or with [mise](https://mise.jdx.dev):

```console
$ mise use -g spm:dankinsoid/diskscope
```

Or from source — macOS 14 or newer:

```console
$ swift build -c release && cp .build/release/dscope /usr/local/bin/
```

## Asking an assistant

Much of the time the shortest route to a clean disk is to let a coding agent
drive. One command teaches it how:

```console
$ dscope skill
installed to ~/.claude/skills/diskscope/SKILL.md
```

Then ask in plain language:

> Where has all my disk space gone? Account for all of it, and tell me what is
> safe to delete.

The skill sets the standard for that answer: scan once and keep the snapshot,
break the disk into categories whose sizes **add up to what is in use**, name
the remainder rather than leaving a gap, and never describe a directory it has
not measured. What a path *means* is the assistant's judgement; every number it
prints comes from a command it ran.

It also carries the traps worth knowing — that a mounted disk image must not be
added to a total, that summing two searches double-counts when one nests inside
the other, that deleting to the Trash frees nothing until the Trash is emptied.

Nothing is deleted without you seeing the paths first: `clean` prints a plan and
does nothing until `--apply`, and the skill says not to pass it until you have
agreed to the specific list.

`--to` installs the skill elsewhere, `--print` writes it to stdout. Every
command takes `--json` with stable field names, so an agent that has never seen
the skill can still use the tool from its output alone.

## Why another one

Drawing a tree of sizes is the easy part. The hard question is *"can I delete
this?"*, and that is what the tool is shaped around.

- **Scan once, ask many times.** A whole disk — five million entries — scans in
  about three minutes and saves to a snapshot that reopens in under a second.
  Filtering and sorting never touch the disk again.
- **Conditions that combine.** Name, size and age in one query, as `find` does.
- **Bulk delete with exceptions.** Clear out every `.build` directory except the
  one you are working in.
- **Sizes you can trust.** They agree with `du` exactly, and the tool accounts
  for the space no directory tree contains rather than leaving it unexplained.
- **Built for agents as much as for people.** Every command takes `--json` with
  stable fields, an installable skill teaches an assistant the tool and its
  traps, and nothing is deleted without a plan you have seen.

## Browsing

Run it with no arguments to scan and explore the result:

```console
$ dscope                      # the whole disk
$ dscope ~/Code               # one directory
$ dscope --snapshot ~/disk.dscope   # a saved scan, instantly
```

Arrow keys or `hjkl` move, `→` enters a directory, `←` goes back, the wheel
scrolls. `/` searches the whole tree, `space` marks an entry, `a` marks
everything listed, `d` moves what is marked to the Trash. `?` lists the keys.

Marking every search result and then unmarking the exceptions is the quickest
way to clear out, say, every `.build` directory but one — the running total of
what would be freed stays on screen.

A directory's long tail of small entries folds into one row that opens like a
folder, so a listing stays readable without hiding anything.

## Asking questions

Save a scan, then query it. A positional path is always scanned; `--snapshot`
reads a saved one.

```console
$ dscope scan / --save ~/disk.dscope

$ dscope scan --snapshot ~/disk.dscope --depth 1 --min 1GB
387 GB	/
256 GB	├── Users/
37.1 GB	├── System/
32.0 GB	├── private/
25.5 GB	├── Library/
23.7 GB	├── Applications/
12.3 GB	└── (15 smaller entries)
```

Entries below the threshold are grouped rather than dropped, so what is shown
still adds up to its parent.

Conditions combine, in the manner of `find`:

```console
$ dscope search --snapshot ~/disk.dscope --name .build --glob --size +500MB
$ dscope search --snapshot ~/disk.dscope --size +1GB --accessed 'over 6m'
$ dscope top --snapshot ~/disk.dscope --dirs-only --modified 'within 7d'
```

`--size` and `--accessed` take `+N` for "at least" and `-N` for "at most", or
the words `over`, `under` and `within` where a leading dash would be read as a
flag. Time units are `h d w m y`. A trailing slash — `--name 'build/'` — means
directories only.

A directory's last use is the newest access anywhere beneath it. Reading a file
does not touch the access time of the directory holding it, so its own
timestamp would report a tree you work in daily as untouched for years.

`--under` re-roots a snapshot on a subtree, so looking inside one directory
costs nothing:

```console
$ dscope scan --snapshot ~/disk.dscope --under ~/Library/Developer --depth 2
```

## Refreshing without rescanning

The filesystem knows which paths changed, so an update re-measures only those:

```console
$ dscope update ~/disk.dscope
re-measured 2 directories in 0.0s, +250 MB
```

On a 60 GB tree that is a fifth of a second against ten seconds to rescan, and
the result matches a full scan exactly.

## Deleting

`clean` prints a plan and changes nothing without `--apply`:

```console
$ dscope clean '.build' ~/Code --glob --size +500MB --except project-a
5.8 GB	/Users/you/Code/project-b/.build
2.6 GB	/Users/you/Code/project-c/.build
kept    	/Users/you/Code/project-a/.build
would free 8.4 GB from 2 entries — re-run with --apply
```

Items move to the Trash, so a mistake is recoverable; `--permanent` skips it.
System locations and the home directory itself are refused outright.

A directory whose name begins with a dot keeps that name in the Trash, and the
Finder hides dotfiles — the Trash can look empty when it is not. Press
Cmd-Shift-. there, or check with `ls -a ~/.Trash`.

## Where the rest of the space went

A directory tree cannot contain everything that occupies a disk, and a scan
says so rather than leaving the gap unexplained:

```console
$ dscope scan --snapshot ~/disk.dscope --depth 0
measured 387 GB of 434 GB in use — 47.3 GB is not in any directory tree
run 'dscope volumes' to see the volumes and APFS snapshots holding it
```

```console
$ dscope volumes
disk3  435 GB used of 460 GB, 25.5 GB free
    /  (ro)
    /System/Volumes/Data
    /System/Volumes/Preboot
    /System/Volumes/VM

3 local APFS snapshots — space no directory tree shows:
  com.apple.os.update-2C083E7D042E96779F886D9092C61E88A0E7AB9EE4C8AC…
Delete with: tmutil deletelocalsnapshots <name>
```

Volumes in one container share a storage pool and all report the same used
figure — never add them up. On one machine Preboot and VM swap held 53 GB
between them, none of it reachable from `/`.

`/` is itself one volume: an external disk mounted elsewhere is never reached by
walking it. `--all-volumes` scans each one and gathers them under a single root,
skipping disk images, whose bytes are the file backing them and already counted.

`dscope access` reports whether Full Disk Access is granted, which a complete
scan of `/` needs. Some directories stay unreadable even with it, because System
Integrity Protection forbids reading them at all.

## How sizes are counted

Sizes match `du` exactly — allocated blocks rather than logical size, so sparse
and compressed files report what they actually occupy. Hard links count once.
Directories reachable by two paths count once, which is what makes a scan of `/`
correct: macOS firmlinks `/System/Volumes/Data` onto `/`, and walking both
reported 759 GB on a disk holding 385 GB.

## Using it as a library

`DiskKit` is the scanner, snapshot format and query layer, without the command
line:

```swift
.package(url: "https://github.com/dankinsoid/diskscope", from: "1.0.0")
```

## License

MIT
