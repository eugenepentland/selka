# Printing, files and command-line authority: how it works

Implementation detail moved out of `docs/io.md`, under the same headings.

## Format strings

An `f"..."` argument is written piece by piece, not built into a `str` first:
`print(out, …)` and `write(out, …)` both send each literal
piece and each hole's rendering straight to the stream. Printing or writing an
f-string therefore allocates nothing when its holes hold an integer, a `float`, a
`bool`, a `str` or `bytes`, with or without a format specification, and the bytes
written are the bytes the interpolation has always written. Each piece is spelled
once: a literal is one write of its bytes, a plain integer, `float` or `bool`
hole is one helper call that spells it into a small stack frame and writes it,
and only a hole with a written specification pays for that specification's
renderer. A hole whose own rendering allocates — a record, a list, a union or an
option — keeps that one rendering, and the pieces are still never joined.

A printed or written f-string is not free, though: it is output, so it costs one
formatting pass per piece and the write behind it. What it saves is the
allocations and the join, not the spelling work.

Using an f-string as a `str` — a binding, a store, an argument or a return value —
makes exactly one allocation: the result's own buffer, sized from the literal
lengths, the text holes' lengths, each scalar rendering's widest spelling and each
specified hole's own measure, and filled in place. A plain hole is never rendered
twice to size the buffer. `f"{text}"` of a value that is already a `str` is that
value, with no allocation at all.

## Stream

**A write to a stream whose reader has gone ends the program quietly.** A write or flush to *standard output* or *standard
error* that fails with `EPIPE`, because nothing reads the other end any more (`prog | head -5`, a closed terminal, a
collector that exited), ends the program at once with exit status 141 and no message: 128 plus `SIGPIPE`, which is what a
shell reports for a program that signal ended and what a Unix tool does there. The runtime keeps `SIGPIPE` ignored, so no
signal is raised and the program is not killed by one; buffered output is not written further, and the program's own status
(what `main` returned) is not used. It holds for `print`, `write` and `flush`, and for a large write as for a short one. `selka run` hands the 141 on as its own status and says nothing of its
own; when its standard error is what has gone (`selka run prog 2>&1 | head`), it stops reading the program's standard
error, and the program ends the same way at its next write there. A `selka test` test never meets it: a test's `out` and
`err` are captured, not written to a descriptor.

**Every other refused write or flush behind a stream differs by stream.** *Standard output* traps: `R_OUTPUT`
(`error[R_OUTPUT]: native execution failed`, then `standard output refused a write`) and exit status 1.
That holds for a full device (`> /dev/full`) and a closed descriptor (`>&-`), whichever of `print`, `write` or
`flush` meets it, and it is never a signal. *Standard error* ignores
the failure: the line or the octets are lost, the program goes on and ends with its own status (0 when `main`
returns 0), so a program cannot learn from a `Stream` that its diagnostics reached nobody. A stream the program
builds itself (`streams.memory()`) never fails. A write to a pipe the program opened itself keeps its own rules and is
not this ending: a file opened on a FIFO whose reader has gone traps `R_FILE` with the reason (`write 'ff': the other
end of the pipe is closed`, status 1); the input of a program it started with `process.run` is dropped from the point
the program stops reading, and the run goes on and answers with that program's status and output; a write to a closed
socket is an error result, or the `R_FILE` trap of a method of an open file.

### Passing the stream as the first argument

The runtime also flushes standard output before it waits for something outside the
program, so a service whose log is standard output shows each line while it waits, and
a signal that ends it there loses none of them. The places are the poller's
`network.wait` (unless its timeout is 0), a blocking read of standard input, of a
connection or of a file handle, `accept_resource` and a blocking connect (`network.connect`,
`connect_within`), `process.run`, `process.wait` and `wait_within` when they may wait,
`time.sleep` on a real clock, and a blocking `durable` lease. Only when the bytes arrive
changes: what the program writes and its order on each stream are what they were. A
program that computes for a long time between prints still holds its output until it
waits, flushes, fills the buffer or ends, and a signal that ends it then loses the buffer
(the program cannot hear a signal): call `flush(out)` for a line that must not wait.

## Runtime diagnostics

A native trap keeps its original code, primary location, call stack and omitted
frame count. Where the failing operation already evaluated the values, the trap
also carries a bounded versioned detail: bounds failures report the original
index (negative values preserved) and the receiver length; integer division and
checked overflow report the evaluated operands and width where available, in the
operation's own signedness: a `u64` overflow reads `left 18446744073709551614`,
not `left -2`, and its record carries `"unsigned":true`. A trap is sticky: the
first trap's detail is retained even if later operations would also fail.

`selka run` renders that detail in text and, with `--diagnostics json`, under
`trap_detail` in the structured diagnostic. Both come from the same captured
values, so text does not reparse its own output and no receiver, index or
expression is reevaluated for a diagnostic. Detail-free traps (step and memory
budgets, capability and host failures) omit the field. Guests are separate
native processes, so children emit exactly one newline-terminated record
`\x1eSELKA-TRAP ` followed by a bounded JSON object on standard error; a host
that sees no record behaves exactly as before, and ordinary standard output,
diagnostics and exit statuses are unchanged.

## Standard input

A program that sits in a shell pipeline reads with `main(stdin: Input, out: Stream)` and writes with `write(out, data)`.
Output is buffered, so a program that answers a peer that waits for the answer calls `flush(out)` after each reply;
without it the peer sees nothing until the program next waits (it reads its next request, for one), the buffer fills or
the program ends. The component worker of the self-hosting
plan is such a program (`selfhost/worker/echo.selka`, specified in the design record
`docs/tooling/component-protocol.md`, "Resident worker v1").

### Records that hold capabilities

The provider state behind a handle lives in the runtime until the process ends, or until the `selka test` trial that
made it ends; nothing in the program destroys it. A program that makes memory filesystems or seeded entropies in a loop
therefore keeps each one until it exits, about 0.6 KiB of runtime memory per filesystem and less per entropy, plus the
entries written to it. A test trial starts with none: its capabilities are fresh stand-ins.

#### A folder named at run time: `filesystem.dir_at`

Narrowing happens once, and a read through the handle costs what it costs through `fs.dir`: the folder's name is joined
to each path as text, as for the literal form. Nothing the checker reports depends on the literal: no report or manifest
lists the folders a program narrows to, so a folder chosen at run time changes no output of `selka check`.

## Processes

Standard output and standard error are read while the input is written, so a child that fills its output before reading
its input does not stall; output beyond the limit is read and dropped (never left in the pipe), and the `truncated`
flag says so. A child that stops reading its input does not take the caller down with a broken pipe. The child starts
with an empty signal mask, the default `SIGPIPE` and only descriptors 0, 1 and 2 (the runtime's other descriptors are
close-on-exec, and any that is not is closed in the child). It gets the caller's environment unless the request gives
one, the caller's working directory unless the request names one, and the caller's other resource limits, with one
exception: its address-space limit (`RLIMIT_AS`, `ulimit -v`) is the one the Selka program itself started with, not the
memory ceiling `selka run` puts on the program (its `--max-memory`, 4 GiB by default, plus 256 MiB). The ceiling bounds
the Selka program; a browser or a compiler it starts reserves address space of its own. The call waits for the child
and has no timeout of its own; to bound a program, run it under `timeout(1)`, or start it and wait with a limit
([below](#starting-a-program-without-waiting)). Like the file builtins, `run_process` and so
`process.run` are refused inside a generic function body; write an ordinary function and call it from the generic one.

### Starting a program without waiting

Only a program this program started can be signalled or waited for, through its Child: the runtime keeps every started
program that no wait has reaped, sends a signal only to one of them, and reaps one only when a wait sees it end, so a
signal never reaches a process number the system has given to someone else. A Selka program that ends while a Child is
still live (a trap, `--timeout`, a signal from outside; ordinary code cannot reach its end without ending its Child)
takes its started programs with it: the system kills each one still running (`PR_SET_PDEATHSIG`). `--restrict` without
`--allow-process` refuses the program that asks for a `Process` before anything starts, as it does for `process.run`.

### Running several programs at once: a group

- **Waiting.** `group_wait_any` answers the key and how the first program to end ended (`exited` with its status in `code`,
  or the signal's number), and the program leaves the group. When several have ended, the one started first answers first.
  A program that ends while nobody waits is not lost: it stays a zombie, held by the runtime, until a wait answers it. The
  wait sleeps in the kernel until a program ends (one `poll` over a `pidfd` of every program of the group, so it takes no CPU
  and answers as soon as one ends); only a kernel without `pidfd_open` (before Linux 5.3) makes it look every 10 ms. It
  is not woken by a `Stop`, so a loop that wants to hear one waits with `group_wait_any_within` and a short limit
  (50 milliseconds) and reads `process.stop_requested(stop)` between waits. Waiting on an empty group fails, since nothing
  could end.

#### How a path is read

How "inside a grant" is decided, so that no spelling of a path reaches a file outside every grant:

- When the run starts, each grant is opened once, and two names are kept for it: the name on the command line made
  absolute against the working directory, and its real path, every symbolic link in it resolved. The working directory
  is taken once too, as the system names it.
- The path is made absolute, and its `.` and empty components are dropped and each `..` removes the component before it,
  as text. A `..` that removes a component of the working directory is exact, because that name has no link in it. A `..`
  that removes a component the program wrote (`a/..`) is accepted only when that component is a directory inside a grant
  and not a symbolic link, which the runtime checks by walking to it; otherwise the system, which follows a link before it
  climbs, could reach another directory than the text names, and the path is refused as outside. A `..` that climbs out
  of a grant named through a link is refused for the same reason.
- The result is inside a grant when it is one of the grant's two names or starts with one of them and a `/`: `g2/a` is
  not inside `g`. When several grants hold it, the one with the longest name serves it. A path that reaches a grant
  through a link of its own (`/home/me/shortcut/g/a`, with `shortcut` a link) names neither and is refused, because the
  text alone cannot tell where the link leads.
- The rest of the path is walked from the directory the grant opened when the run started, one component at a time and
  only downwards, and no symbolic link is followed, on the way or at the end; an append refuses a link at its end, and
  only regular files are read or written. A link made inside a grant after the start, a grant renamed or replaced by a
  link, or a name that spells its way around a grant with `..`, cannot move that walk out of the grant's directory.

### Listings with entry kinds

An `Entry` has `name: str` and `kind: PathKind` (`Regular`, `Directory`, `Symlink` or `Other`, the kinds `stat` reports).
The kind is the directory record's own (`d_type`), so the listing is as cheap as `listdir`: a read of the directory and no
`stat` of any entry. (An entry whose record carries no type, which a few filesystems report for every entry, costs one
`fstatat` of that entry.) It is the entry's own kind, as `stat` reports it and `stat_follow` does not: a symbolic link
is `Symlink` even when it names a directory, and `list_entries` of that link fails with `is not a directory` in every run,
while `fs.listdir` of it lists the folder it names in a run without `--restrict` (under a restriction or a narrowing both
refuse it). To list what the link points at, list `filesystem.realpath(fs, path)`, the folder's own name, which a
restriction allows while the folder is inside a grant. A real
directory lists in the system's order, `filesystem.memory()` sorted by name, and a directory of any size lists whole
([above](../io.md#large-directories-and-listing-bounds)). A path that is not a directory, is missing or is refused fails with
`directory listing 'path': ...` and the reason, never the grants unless a grant is the cause. A listing, like a stat, opens the
directory with one `openat` from a descriptor the capability keeps (no descriptor is duplicated; a path of more than one component
under a grant adds one confined `openat2`). The builtin
`list_entries_path` answers the packed octets the typed function decodes: for each entry a kind octet (1 regular file,
2 directory, 3 symbolic link, 0 anything else), a little-endian 16-bit name length and the name.

### Rename, stat and file locks

A stat is one `fstatat` of the path relative to a directory the capability keeps open. Without a restriction the whole
path goes to that one call, which follows the links on the way (unless the handle is narrowed by `fs.dir`, which takes the
route of a grant); under a grant a path of one component is that same single call, and a deeper path adds one `openat2` (a
single call that refuses every symbolic link on the way and cannot leave the granted directory) and the close of the directory
it returns. No descriptor is duplicated for the call and no directory on
the way is opened one component at a time (it was three to five system calls without a restriction, and up to thirteen under a
grant). A kernel without `openat2` walks a granted path component by component, as before. The directory on the way is
opened for its search permission only, so a directory with no read permission no longer stops a stat below it.

### Replacing a file without forcing it to disk

`atomic_write_file` makes its bytes survive a power loss, and pays for it: it synchronizes the file before the rename and
the directory after it, two `fsync`s that took 8 ms a write on this machine's ext4 disk on 8 November (40 ms on 7
November and up to 130 ms in a later run, so read the ratio, not the milliseconds). Most rewrites need less, and two more pairs
of calls say how much. `replace_file(fs,
path, data)` and `fs.replace_file_mode(path, data, mode)` publish the same way, a temporary beside the destination renamed
over it, and force nothing to disk, as Zig's `std.fs.AtomicFile` does. `fs.replace_file_synced(path, data)` and
`fs.replace_file_synced_mode(path, data, mode)` force the file to disk before the rename and not the directory after it,
the middle course a Zig program takes when it syncs its temporary file before `AtomicFile` renames it: one `fsync` where
the durable call makes two. 50 rewrites of a small file took 382 to 409 ms with `atomic_write_file` (100 `fsync`), 194 to
228 ms with `replace_file_synced` (50 `fsync`, the file's) and 5 to 12 ms with `replace_file` (none).

| | `atomic_write_file[_mode]` | `replace_file_synced[_mode]` | `replace_file[_mode]` |
| --- | --- | --- | --- |
| Cost of a small write on ext4, 8 November | about 8 ms | about 4 ms | well under 1 ms |

### Real paths, permissions and times

`canonical_path` resolves every symbolic link, as `realpath(3)` does, and a missing path fails. **Without a
restriction and under `--allow-read` and `--allow-write` grants** it answers the absolute, link-free path, and
`filesystem.cwd(fs)` (the `realpath` of `.`) is the process's working directory, so the name means the same file in a
plain and a restricted run (under a grant the working directory must itself be inside one). **On an `fs.dir(...)`
narrowing** it answers the path relative to the narrowing, so a program learns nothing of the host's layout beyond it:
the directory itself is the empty string `""`, which every directory operation accepts, and the name is a valid argument
to every other call on the same handle. Under a grant or a narrowing a link is followed only while it stays inside the
directory: an absolute link, or one that climbs out of it, fails with
`resolves outside the granted directory`, and so does a missing path behind such a link, so a failure leaks nothing
about what lies outside. (Every other operation refuses a symbolic link under a restriction, or through an `fs.dir(...)`
narrowing in any run, outright, an append (`open(path, "a")`) too: it writes nothing through a link and creates nothing
through a dangling one; only `canonical_path` and `stat_follow_path` resolve one.)

`stat_follow_path` and `filesystem.stat_follow` are `stat_path` and `stat` that follow a symbolic link at the end of the
path and describe its target, as Zig's `statFile` does; a link to nothing is `Missing`, and the same confinement
applies under a restriction. Without a restriction it answers what `stat(2)` answers, so `/dev/stdin`, `/dev/fd/0` or
`/proc/self/fd/0` when standard input is a pipe is a `Stat` of kind `Other`, as `/dev/null` is. Under `--restrict` and
through `fs.dir(...)` such a path is refused, as `fs.open` of it is: it is outside the grants, or it is a link out of the
granted folder (`resolves outside the granted directory`, where `fs.open` says it does not follow the link).

`chmod_path` sets the permission bits (`0` to `0o7777`; anything else fails with `the mode must be between 0 and
0o7777`), `touch_path` sets the access and modification times of an existing path to now, and `set_modified_path`
sets the modification time to `nanoseconds` since the Unix epoch and leaves the access time. None of them follows a
symbolic link at the end of the path: `chmod` of a link fails (`a symbolic link has no permission bits of its own`),
and `touch` and `set_modified` change the link itself. `touch_path` does not create a missing path, so a racing delete
cannot leave an empty file behind; write the file first.

`fs.symlink_path(target, path)` creates the symbolic link `path` holding the text `target`, written target first as `ln -s TARGET
LINK` and Zig's `symLink` take it. It is a write like the others: it needs write authority, the link's directory must be
inside a write grant and exist, and a path outside every grant, inside only a read grant, or already taken is refused
(`symlink 'path': already exists`, `denied: 'RESOLVED' is outside the granted directories`). The target
is only text: relative to the link's directory, absolute, or naming nothing, it is stored as written and is not looked at,
since a link does nothing until a call follows it, and the two calls that do (`canonical_path` and `stat_follow_path`)
follow it only while it stays inside the granted directory. Every other call refuses a link on the way to its path, and
a read, a write, an append or a lock of a link itself, so a program that makes one can build the tree that tests of that refusal need:
`fs.symlink_path("/etc", "outside")` then `fs.read_regular_file("outside/passwd", 100)` fails with `is a symbolic link
the sandbox does not follow`. `stat_path` of the link answers `Symlink` with its size the length of its target, `remove`
unlinks it and `rename_path` moves it. The target holds from 1 to 4094 octets and no NUL (`the link target must be text of 1
to 4094 octets with no NUL`).

`fs.link_path(target, path)` and `filesystem.link(fs, target, path)` create the hard link `path` to the existing file `target`
(`link(2)`, written target first as `ln TARGET LINK` and `symlink` take it): a second name for one file. The two names are
equal. They share the bytes, the permission bits, the times and the inode, so a write through either is read through the
other, `Stat.inode` is the same for both and `Stat.links` reads 2 for both; removing one name leaves the other with the file
and a count of 1, and a publication over one name (`atomic_write_file`, `replace_file` and the rest rename a new file over
it) makes that name a new file and ends the sharing, as on disk. A program that restores an archive makes a member that is
a second name for an earlier one with this call, and a program that wants a name to survive a rewrite of another uses it
instead of a copy.

Each of the two paths is resolved as `symlink` resolves its own ("How a path is read" above), and the call writes both: the
directory that holds the new name gets an entry, and the file gets a name it can be reached by, so a program that may only
read a file can never link it into a place it can write (it would then write the file). Under `--restrict` both paths
must fall inside write grants, the same grant or two, and two grants on different disks answer `the paths are on different
filesystems`. On a handle narrowed by `fs.dir` or `filesystem.dir_at` both stay inside its folder (no `..`, `.`, leading `/`
or empty part), and `fs.read_only()` refuses the call. No link is followed on the way to either name or at the end of
`target`. `target` must be a regular file: a folder fails with `is a directory`, a symbolic link (even one that names a
regular file) with `is a symbolic link the sandbox does not follow, or links nest too deeply`, and a pipe, socket or device
with `is not a regular file`, so the call cannot name a folder twice or reach through a link. A `path` that is taken fails with
`already exists` and one in a folder that does not exist with `the path does not exist`. A failure names both ends, as a
rename's does: `link 'TARGET' to 'PATH': REASON`.

| Root | `link(fs, target, path)` |
| --- | --- |
| no restriction | the paths are read as a process reads them (a link on the way is followed, `..` and an absolute path are accepted); the source is never a link or a folder |
| `--restrict` write grants (`--allow-write`) | each path must fall inside a write grant (an absolute one too); a path outside every grant fails with `denied: 'RESOLVED' is outside the granted directories`, one inside a read-only grant with `denied: writing needs a write grant (--allow-write); 'RESOLVED' is granted for reading only`; a link on the way or at the end is refused |
| a directory narrowed with `fs.dir(...)` | both paths inside its folder under its own rule, in any run; a link on the way fails with `a parent of the path is not a directory` |
| `fs.read_only()` | `denied: this Filesystem was narrowed by fs.read_only() and does not write` |
| `filesystem.memory()` | the same as a grant, with one shared file ([below](#the-durable-calls-on-a-tests-filesystem)) |

`fs.mkdir_mode(path, mode)` and `filesystem.mkdir_mode(fs, path, mode)` create the folder `path` with the permission bits `mode`
(`0` to `0o7777`; anything else fails with `the mode must be between 0 and 0o7777`), as `mkdir(2)` takes them. The folder has
that mode from the moment it exists. `fs.mkdir(path)` followed by `chmod` does not: the folder is first made with the default
mode (`0o775` under the usual umask) and is open to every member of the group until the `chmod` runs, which a program
extracting an archive that records a folder `0o700` cannot accept. The process's umask narrows `mode` as it
narrows the mode of a file (`atomic_write_file_mode`), so `0o700` is `0o700` and `0o777` is `0o775` under `0o002`, and the
system keeps the nine permission bits and the sticky bit and leaves the set-user-ID and set-group-ID bits to `chmod`. A
program that wants a mode exactly, whatever the umask, makes the folder with an owner-only mode, fills it and then
sets the mode: a mode the umask would narrow is then never granted early, and a folder recorded `0o555` can be filled
before it stops being writable. The path is read as `fs.mkdir` reads it (a trailing slash names the folder to make), its
directory must exist and be both readable and writable, and a path that is taken fails with `already exists` and one in a
folder that does not exist with `the parent directory does not exist`; the failure reads `mkdir 'PATH': REASON`. The same
rules as `link` decide where the call may write: write grants, the folder of a narrowed handle, no link on the way, and a
refusal from `fs.read_only()`; a test's `memory()` filesystem stores the mode as given, since it has no umask.

`fs.create_mode(path, mode)` and `filesystem.create_mode(fs, path, mode)` are the counterpart for a file written in pieces: they open `path` for writing as `fs.open(path, "wb")` does, and a file they create has the permission bits `mode`
(`0` to `0o7777`) from the `open(2)` that makes it, as `creat(2)` takes them. `fs.open(path, "wb")` followed by `chmod` leaves
an archive member recorded `0o600` readable by the group for as long as it takes to fill. The umask narrows `mode` as it
narrows `mkdir_mode`'s. A file that already exists is what `fs.open(path, "wb")` makes of it: truncated to nothing, its
mode and owner kept (a program that wants the recorded mode on it too calls `chmod`, or removes the file first). The path
is read as every write reads one: under `--restrict` inside a write grant with no link followed, on a narrowed handle
inside its folder, refused by `fs.read_only()`; without a restriction a final link to an existing file is followed and a
pipe or a device is written, as `fs.open` does. A failure reads `open 'PATH': REASON`. The result is a `File` like the one
`fs.open(path, "wb")` gives, and `with fs.create_mode(path, mode) as f:` opens it as `with fs.open(...)` does. A test's
`memory()` filesystem gives a new file the mode as given.

`Stat` also carries `changed`, the status-change time (`ctime` of `stat(2)`), a sixth word of `stat_path`'s answer: the
nanosecond of the last change to the entry, a write, a rename, `chmod` or `set_modified`. It is the time a program cannot
set back: `set_modified_path` can give a rewritten file the modification time it had, and the kernel still moves
`changed`, which is why a tool that remembers a file by its identity compares it as well as the modification time.

`atomic_write_file` publishes with mode `0600`, because the private cache and journal writers rely on it.
`atomic_write_file_mode` is the same publication (a complete file or the previous one, never a partial) with the
temporary created with `mode`, so the file appears with those permissions, on a replacement too; the process umask
applies as it does to `open(2)`, so `0o666` becomes `0o664` under the common umask `0o002`.

`fs.read_link_path(path)` and `filesystem.read_link(fs, path)` answer the text stored in the symbolic link at `path`, exactly
as `symlink` stored it or `ln -s` wrote it, as `readlink(2)` does: relative or absolute, naming something or nothing, and
for a link to a link the text of the first link only. The link is never followed, so what it names is not looked at: a
dangling link, and a link whose target is outside the granted directory, are read like any other, because the text gives no
access to its target (a program that wants the target follows it with `realpath` or `stat_follow`, and meets their
confinement). The path is resolved as `stat_path` resolves it, on every kind of root, so `read_link` refuses what `stat`
refuses for the same path and nothing more:

| Root | `read_link(fs, path)` |
| --- | --- |
| no restriction | the links on the way to the final component are followed, an absolute path is accepted |
| `--restrict` grant (`--allow-read`, `--allow-write`) | the path must fall inside a grant (an absolute one too); a link on the way is refused (`is a symbolic link the sandbox does not follow, or links nest too deeply`); the final link is read |
| a directory narrowed with `fs.dir(...)` | the same as a grant, in any run, the narrowing's own prefix included; a link in the directory may name a target outside it |
| `fs.read_only()` | the same as the handle it narrows: reading a link needs read authority only |
| `filesystem.memory()` | the same as a grant, answered from the stand-in's links |

A `.` or `..` component means what it means to the system, as for every durable call, except on a handle narrowed by
`fs.dir` or `filesystem.dir_at`, which refuses it. An entry that is not a link (a file, a directory, the root `""`) fails with `read link 'PATH': is not a symbolic link`, a path with nothing at it, or under a directory that does not
exist, with `the path does not exist`, and a target that is not valid UTF-8 text with
`the bytes read are not valid UTF-8 text`. A link another program made may hold up to 4095 octets, which `read_link` reads
whole (`symlink` makes links of 1 to 4094).

### The durable calls on a test's filesystem

`filesystem.memory()`, and so the `fs: Filesystem` parameter of a test, answers every durable operation on this page
from its own entries: `atomic_write_file[_mode]`, `replace_file[_mode]`, `replace_file_synced[_mode]`, `rename_path`, `stat_path` and `stat_follow_path`, `sync_directory`,
`canonical_path`, `chmod_path`, `touch_path`, `set_modified_path`, `symlink_path`, `read_link_path`, `link_path`, `mkdir_mode`, `create_mode`, `read_regular_file`, `list_directory` and the three
locks. A test therefore runs the code a program ships, not a plain write standing in for the atomic one. The grants and
the path rules are the real ones (`fs.read_only()` refuses the writes, `fs.dir(path)` scopes the paths, a path is
relative and has no `.` or `..` component, and only the directory operations take the empty path for the root), and so
is the wording of a refusal. An embedding provider that cannot promise durability still refuses with `durable native
filesystem provider is unavailable`.

Everything is deterministic and needs no flag, so a test that uses these calls is cached like any other:

- **Modes and inodes.** A file is created `0644` and a directory `0755`; the root is a directory `0755` with inode 1.
  Inode numbers count up from 2 in the order entries are created. A rename keeps the inode, the mode and the time of
  what it moves; an `atomic_write_file` over a file is a new inode (a `File` that already holds the old file keeps
  reading it). There is no umask: a mode is stored exactly as given, so `fs.atomic_write_file_mode(path, data, 0o666)`
  is `0o666`, and `chmod` and `stat` round trip. The modes are honoured, too: see [permission bits on the in-memory
  filesystem](#permission-bits-on-the-in-memory-filesystem).
- **Times.** `Stat.modified` reads a logical clock that starts at 946684800 seconds (1 January 2000, the epoch of the
  test clock) and moves one second for each call that changes the filesystem: creating or truncating a file, the first
  write of an open `File`, `mkdir`, `remove`, `rename_path`, `atomic_write_file[_mode]`, `touch_path`, and the file a
  lock creates. The call stamps what it changed with the new reading: the file, and the directory that gained, lost or
  renamed an entry. `set_modified_path` stores the time it is given and `chmod_path` changes no modification time, so
  neither moves the clock, and a call that fails does not either. No test sleeps to make a file newer than another.
  `Stat.changed` is the same reading for a call that writes, and for `chmod_path` and `set_modified_path`, which leave the
  clock where it is, the nanosecond after the last change: it is later than every earlier change, so a file rewritten and
  given its old `modified` back still reads a newer `changed`.
- **Symbolic links** are entries `symlink_path` makes, holding their target text with mode `0777` and a size of that text's
  length; `Stat.kind` is `Symlink` for one. The rules are the granted directory's: `canonical_path` and `stat_follow_path`
  follow a link only while it stays inside the filesystem (an absolute target, or `..` past the root, fails with `resolves
  outside the granted directory`, more than 40 links in one walk with the link-nesting refusal, and a link to nothing is
  `Missing` to `stat_follow`), and every other call refuses a link on the way or a read, write or lock of one itself with the
  real wording; `read_link_path` answers the text of the link itself, a target outside the filesystem included, and says
  `is not a symbolic link` of any other entry. A listing names a link `Symlink`, `chmod_path` of one fails (`a symbolic link has no permission bits of its
  own`), `touch_path` and `set_modified_path` change it, and `remove` and `rename_path` move or unlink the link itself.
- **Hard links** are second entries for one file that `link_path` makes: they share the bytes, the mode, the times, the inode and the
  lock, so a write, a `chmod`, a `touch` or a lock through one name is seen through the other, `Stat.links` counts the names (and
  is 2 for both after one `link`), a removal or a rename of one name leaves the other, a rename of one onto another name of the
  same file does nothing, and a publication over one name makes it a new file. A handle that holds a removed name keeps the file
  and sees what the other name writes. A link changes the file's status time and its directory's modification time. The source
  must be a regular file (a folder is refused with `is a directory`, a symbolic link with the link wording); the new name must be
  free and in a directory the stand-in may write. `mkdir_mode` stores the nine permission bits and the sticky bit as given (there is
  no umask) and drops the set-user-ID and set-group-ID bits, as the system does; `create_mode` gives a new file the mode as given.
- **Listings** are sorted by name (the real provider answers in the system's order), and hidden names are included.
- **Locks** are held on the entry, as `flock` holds an inode, until the `File` that `lock_directory`, `lock_file` or
  `try_lock_file` returned is released: on `return`, on `fail`, when the `with` block falls through, and when a trap
  ends the test and the filesystem with it. `try_lock_file` and a second `lock_directory` on a held path fail with `: the
  lock is held by another holder` (`filesystem.is_lock_busy` is true). `lock_file` would wait for the holder, but a test
  has one thread to release it, so it fails at once with `: the lock is held (a stand-in cannot wait)`. A lock is
  advisory: it does not stop reads or writes, and `lock_file` creates a missing file with mode `0600`, as the real one
  does.

### Permission bits on the in-memory filesystem

`filesystem.memory()`, and so a test's `fs`, keeps a mode for every entry (`0644` for a file and `0755` for a directory unless
`chmod_path` or a `_mode` publication set another) and honours it: the stand-in acts as an ordinary user who owns every entry, so
the **owner** bits of the mode decide, the way they do on disk for any user but a privileged one (which passes every check, and
which a test never is). Group and other bits, the set-user-ID, set-group-ID and sticky bits and the owner of an entry play no part.
A call that the bits forbid fails with the real provider's words, `permission denied` in the message of the call, and changes
nothing. Three bits are asked for:

- **read** (`4`): of a file, to read it; of a directory, to list it, or to open it for reading;
- **write** (`2`): of a file, to write into it in place; of a directory, to add, remove or rename one of its entries;
- **search** (`1`): of every directory above the path, so no path goes through a directory without it.

| Call | Search | Then it needs |
| --- | --- | --- |
| `read_file`, `read_text`, `open(path, "r")` | every directory above | read of the file |
| `read_regular_file`, `read_at` | every directory above | read of the file, read of its directory |
| `write_file`, `write_text`, `open(path, "w")` and `"a"` of an existing file | every directory above | write of the file |
| the same of a file that does not exist yet | every directory above | write of its directory |
| `mkdir` | every directory above | write of its directory |
| `remove` of a file or an empty directory | every directory above | write of its directory |
| `atomic_write_file[_mode]`, `replace_file[_mode]`, `replace_file_synced[_mode]` | every directory above | read and write of its directory (never the destination's own mode) |
| `symlink_path` | every directory above | read and write of its directory |
| `link_path` | every directory above both paths | read and write of both directories (the source file's own mode is not asked) |
| `mkdir_mode` | every directory above | read and write of its directory (`mkdir` asks for the write bit alone) |
| `create_mode` | every directory above | write of an existing file, or write of its directory for a new one; read of its directory |
| `rename_path` | every directory above both paths | read and write of both directories; write of a moved directory that changes parent |
| `lock_file`, `try_lock_file` | every directory above | read and write of an existing file, or write of its directory for a new one; read of its directory |
| `lock_directory`, `sync_directory` | every directory above | read of the directory, and read of the directory that holds it |
| `listdir`, `list_directory`, `list_entries` | every directory above | read of the directory |
| `chmod_path`, `touch_path`, `set_modified_path` | every directory above | read of its directory |
| `stat_path`, `stat_follow_path`, `statfs_path`, `read_link_path`, `canonical_path`, `exists` | every directory above | nothing |

Some details follow the real provider, not what `chmod` suggests. A creation in a directory without the write bit fails with
`permission denied` for every call (`write_file`, `write_text` and `open(path, "w")` try to create the file and then to open an
existing one; when both find nothing, the answer is the first one's reason). A durable call that creates, removes or renames needs the read bit of the directory as well as the write bit,
because the real provider opens that directory for reading to reach the path, and `chmod_path`, `touch_path` and
`set_modified_path` need that read bit too; `exists` of a path the search bit hides is `False`. A read-only file in a writable
directory is replaced by a publication (the new file is renamed over it) and refuses an in-place write, as on disk, so the way
to make an install fail in a test is a directory without the write bit. A stat of a directory itself needs nothing of the
directory, only of those above it. An open file keeps working when `chmod` changes its mode afterwards, as on disk.

The table is pinned against a real directory: `test/fs_permissions_cli_test.zig` runs one program of about 490 calls on a real
directory and on `filesystem.memory()` and requires both to print the same file, `test/fixtures/fs-permissions/expected.txt`.
