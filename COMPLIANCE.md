# Making a repo compliant with `tlib`

This is the full checklist and reference for getting a GitHub repo to
install cleanly with `tlib install`. Everything here is derived directly
from `ZSH.zsh` — if your repo satisfies these rules, `tlib install` will
work; if it doesn't, this doc tells you exactly which check fails and why.

There are two repo shapes `tlib` understands. Use `info.xml` unless you
have a specific reason to use the legacy shape — it's more capable and
the error messages are clearer.

---

## 0. Quick start: publishing a repo, start to finish

1. **Write your command.** Any single script or prebuilt executable —
   shell, Python, Node, a compiled binary, whatever.
2. **Add an `info.xml` at the repo root** (see section 2) describing it.
3. **Test locally, before pushing anything:**
   ```bash
   tlib local /path/to/your/repo
   ```
   This runs the real install logic against your working directory —
   no download, no need to push first. Fix everything it flags.
4. **Uninstall your test install** so you're testing cleanly next time:
   ```bash
   tlib uninstall local/<your-repo-dirname>
   ```
5. **Push to GitHub, on the branch you expect people to install from**
   (usually `main` — see section 1 on why the branch name matters).
6. **Test the real thing**, exactly the way a stranger would:
   ```bash
   tlib install YourGitHubUsername/your-repo
   tlib uninstall YourGitHubUsername/your-repo
   ```
   Do this from a directory that isn't your repo clone, so you're not
   accidentally relying on files only present in your working copy.
7. **Tell people how to install it.** Copy the pattern from this repo's
   own README: a `tlib install Owner/Repo` line, and what command(s) it
   gives them.

If step 3 or step 6 fails, section 7 below decodes the exact error
message you're looking at.

---

## 1. Baseline requirements (both shapes)

- [ ] **The repo is public.** `tlib install` downloads
      `https://github.com/<owner>/<repo>/archive/refs/heads/<branch>.tar.gz`
      with an unauthenticated `curl` request. A private repo (or a typo'd
      owner/repo) returns HTTP 404, and `tlib` reports "GitHub repo or
      branch not found."
- [ ] **The branch you're installing from is actually named what you
      think.** Plain `tlib install Owner/Repo` always assumes `main`. If
      your default branch is `master` (or anything else), installs fail
      with the same 404 unless the installer explicitly names the branch
      via a `raw.githubusercontent.com/.../<branch>/` URL.
- [ ] **`info.xml` (or `make.sh` + `src/`) lives at the repo root** — not
      in a subdirectory. `tlib` looks for `info.xml` at
      `<downloaded-repo>/info.xml`, full stop.

---

## 2. `info.xml` shape (preferred)

Minimal skeleton:

```xml
<tlib version="1">
  <package name="my-tool" version="1.0.0">
    <requires>
      <tool name="node"/>
    </requires>
    <commands>
      <command name="my-tool" source="my-tool.js" language="node"/>
    </commands>
  </package>
</tlib>
```

**The `<package>` wrapper is decorative.** `tlib` never reads `name=` or
`version=` on `<package>` — it just looks for `<command>` and
`<requires>`/`<tool>` elements anywhere in the file. You can nest them
under `<package>` for readability (recommended, since that's the
convention every real repo follows) or put them directly under `<tlib>`
— both work identically. There's currently no version-compatibility
mechanism at all: `tlib` doesn't compare your `version=` against
anything, so bumping it doesn't do anything functional. Likewise, a
`<platforms><platform name="macos"/></platforms>` block (you may see this
in some repos) is **silently ignored** — `tlib` has no OS-gating logic,
so it does not stop someone on a different platform from attempting an
install that may then fail on missing tools.

### 2.1 `<requires>`

- Lists tools that must already be on the installing machine's `PATH`.
  Checked with a plain `command -v`, **before** anything else in the file
  is processed.
- Accepts `<tool>`, `<require>`, or `<dependency>` as the tag name, and
  either a `name=` attribute or bare text content (`<tool>node</tool>`).
  These can appear anywhere in the file, not just inside `<requires>`.
- If a listed tool is missing, the whole install aborts immediately with
  `<tool> is required for info.xml requirement` — no partial install.
- **Compliance tip:** only list tools your commands' `build=` steps or
  runtime actually need. Don't require `python3` if none of your commands
  use it — every install of your repo pays that cost.

### 2.2 `<command>` — required fields

Each command needs:

- A **name**: `name=` (or `id=`). If omitted, it's derived from `source`'s
  filename without extension. Must match `^[A-Za-z0-9._+-]+$` — no
  slashes, no spaces, no `.` or `..` alone. **Compliance failure:**
  `command #N has invalid or missing name`.
- **Exactly one** of `source`, `build`, or `output` present (you can
  combine `build` + `output` together — see below). Missing all three:
  `command '<name>' needs source, build, or output`.
- A **unique name** across the whole file. Duplicate:
  `duplicate command names: <name>`.

A repo can declare as many `<command>` elements as it wants — each one
becomes a separate installed command. There's no requirement that a
command's name match the repo name.

### 2.3 Picking how a command gets built

**`output` only (no `source`, no `build`)** — the file is already built
and checked into the repo (e.g. a prebuilt binary or a hand-written
wrapper script under `bin/`). Used as-is.

```xml
<command name="my-tool" output="bin/my-tool"/>
```

- Compliance: the path must exist in the repo and must stay **inside**
  the repo — no absolute paths, no `..`. Violation: `output for command
  '<name>' must be a relative path inside the repo`.
- If the referenced file doesn't exist: `declared output for command
  '<name>' does not exist: <path>`.
- **Compliance tip:** the file must actually be committed to the repo —
  a `.gitignore` that excludes `bin/` (very common for build output
  directories) will silently ship an empty directory, and installers get
  the "does not exist" error with no obvious cause. Double check with a
  fresh clone, not just your working copy.

**`build` (with or without `output`)** — runs a shell command in the repo
root first (e.g. `npm install`, `make`, `cargo build --release`), then
locates the result.

```xml
<command name="my-tool" build="npm install" output="bin/my-tool"/>
```

- If you omit `output`, `tlib` searches, in order: `<repo>/<name>`,
  `<repo>/build/<name>`, `<repo>/dist/<name>`, `<repo>/bin/<name>`,
  `<repo>/.build/release/<name>`, `<repo>/.build/debug/<name>`, then its
  own build scratch directory. **Compliance tip:** if your build output
  doesn't land in one of those exact paths under that exact name, always
  set `output=` explicitly — don't rely on the search order.
- If the build command itself fails (non-zero exit), install aborts with
  `command failed with exit <N>: <your build command>`.
- **Compliance tip:** `build=` runs exactly the string you write, in the
  repo root, on the installer's machine — not yours. Don't write a build
  command that assumes tools, env vars, or paths only your dev machine
  has. If it needs something beyond what a plain `git clone` gives you,
  that something belongs in `<requires>`.

**`source`** — a source file `tlib` builds or wraps for you, dispatched by
`language=` (or by the file's extension if `language` is omitted):

| `language` value(s) | What happens | Needs on the installer's machine |
|---|---|---|
| `c` | `clang <source> -o <out>` | `clang` |
| `cpp`, `c++` | `clang++ <source> -o <out>` | `clang++` |
| `objc`, `objective-c`, `m` | `clang -fobjc-arc`, framework from `frameworks=` or auto-detected (`AppKit`/`Cocoa` in source → AppKit, else Foundation) | `clang` |
| `swift` | `swiftc <source> [+ sources=] -o <out>` | `swiftc` |
| `shell`, `sh`, `bash`, `zsh` | copied as-is, chmod +x | nothing |
| `python`/`node`/`javascript`/`js`/`ruby`/`perl`/`php`/`lua` | wrapped in a `#!/bin/sh` shim that execs the interpreter against your source file (override interpreter with `interpreter=`) | that interpreter |
| `go` | `go build -o <out> <source>` | `go` |
| `rust`, `rs` | `rustc <source> -o <out>` | `rustc` |
| `copy`, `binary`, `prebuilt` | copied as-is, chmod +x | nothing |

Extension-to-language auto-detection (used only when `language=` is
omitted): `.c`→c, `.cc/.cpp/.cxx`→cpp, `.m`→objc, `.swift`→swift,
`.py`→python, `.sh/.zsh/.bash`→shell, `.js/.mjs`→node, `.rb`→ruby,
`.pl`→perl, `.php`→php, `.lua`→lua, `.go`→go, `.rs`→rust.

- **Compliance tip:** if you need a compiled/interpreted language, list
  the matching tool in `<requires>` so `tlib doctor` warns installers
  *before* they hit a failed build, not during it.
- `args=` (aliases: `compiler-args`, `flags`) passes extra flags straight
  through to the compiler/build invocation.
- `source`, `output`, and every path in `sources=` must be relative paths
  inside the repo — same rule as `output` above.
- **Compliance tip:** the interpreter-wrapper shim (`python`/`node`/etc.)
  execs your source file **at its path inside the persistent download
  cache** (`~/.tlib/repos/<owner>/<repo>/<branch>/...`), not a copy — so
  if your script does relative-path file I/O based on its own location,
  make sure that still works from that path, not just from your repo
  clone.

### 2.4 Field name aliases

Most fields accept more than one attribute name (use whichever reads
best in your `info.xml` — they're interchangeable):

| Canonical | Aliases |
|---|---|
| `name` | `id` |
| `source` | `src`, `file`, `path` |
| `language` | `lang`, `type`, `compiler` |
| `interpreter` | `runtime` |
| `build` | `build-command` |
| `output` | `out`, `binary`, `install-from` |
| `args` | `compiler-args`, `flags` |

---

## 3. Legacy shape (`make.sh` + `src/`)

Only use this if you have a reason not to use `info.xml` — it's less
capable (no `<requires>` checking, smaller language set, no `build=`
declarations independent of `make.sh`).

- [ ] A `make.sh` at the repo root — runs first, from the repo root.
- [ ] One or more files directly under `src/` — command name = filename
      without extension.
- [ ] For each `src/` file, if `make.sh` already produced a matching
      executable (same search-path rule as `output` resolution above),
      that's used. Otherwise `tlib` compiles it itself, using this
      **smaller** language set: `c`, `cc`/`cpp`/`cxx`, `m`, `swift`,
      `sh`/`zsh`/`bash`, `py`, `js`/`mjs`, `rb`, `pl`, `php`, `lua`. No
      `go`, `rust`, `copy`/`binary`/`prebuilt`, and no custom
      `interpreter=` override — if you need any of those, use `info.xml`
      instead.
- [ ] At least one command must actually get installed, or the whole
      install fails with `no source files found in src/`.

---

## 4. Test before you publish

```bash
tlib local /path/to/your/repo
```

Runs the exact same `info.xml`/legacy install logic against a local
directory — no download, no need to push first. Fix everything this
flags before you push and tell anyone to `tlib install` your repo.

```bash
tlib doctor
```

Shows what's on *your* machine — useful for confirming which optional
compiler toolchains you personally have, so you know which of your
`<requires>` entries you can actually test locally.

**A local test only proves the file *your working copy* has works.** It
does not prove the version on GitHub does. Before telling anyone to
install your repo, also do the real thing at least once — clone fresh
somewhere else (or just run `tlib install Owner/Repo` from any directory
that isn't your repo clone) so you're testing exactly what a stranger
would get, including whatever's actually committed and pushed.

---

## 5. Worked examples

A few complete, copy-adaptable `info.xml` files for common patterns.

**A single shell script:**

```xml
<tlib version="1">
  <package name="hello" version="1.0.0">
    <commands>
      <command name="hello" language="shell" source="hello.sh"/>
    </commands>
  </package>
</tlib>
```

**A Python script that needs `python3`:**

```xml
<tlib version="1">
  <package name="stock-checker" version="1.0.0">
    <requires>
      <tool name="python3"/>
    </requires>
    <commands>
      <command name="stock-checker" output="bin/stock-checker"/>
    </commands>
  </package>
</tlib>
```

(This example uses a hand-written `bin/stock-checker` wrapper script that
`exec`s `python3` against the real script, rather than `language="python"`
directly, so it can resolve its own path inside the persistent tlib
download cache — see the compliance tip in 2.3. This is the same pattern
this repo's own `tlibUpdater` install uses.)

**A Node app that needs a build step:**

```xml
<tlib version="1">
  <package name="my-server" version="1.0.0">
    <requires>
      <tool name="node"/>
      <tool name="npm"/>
    </requires>
    <commands>
      <command name="my-server" build="npm install" output="bin/my-server"/>
    </commands>
  </package>
</tlib>
```

**A compiled Go tool:**

```xml
<tlib version="1">
  <package name="my-cli" version="1.0.0">
    <requires>
      <tool name="go"/>
    </requires>
    <commands>
      <command name="my-cli" source="main.go" language="go"/>
    </commands>
  </package>
</tlib>
```

**Multiple commands from one repo:**

```xml
<tlib version="1">
  <package name="my-tool" version="1.0.0">
    <requires>
      <tool name="lsof"/>
    </requires>
    <commands>
      <command name="my-tool" build="npm install" output="bin/my-tool"/>
      <command name="my-tool-stop" language="shell" source="bin/my-tool-stop"/>
    </commands>
  </package>
</tlib>
```

---

## 6. A note on trust, for repo authors and installers

`build=` and every `source=` compile/interpret step run with the
installing user's full permissions, on their machine, with no sandboxing
of any kind — this is exactly as much trust as running any script you
downloaded from the internet, because that is literally what's
happening. `tlib` does not scan, sandbox, or ask for confirmation before
running your `build=` command or executing your `source` file's
interpreter shim.

- **As a repo author:** don't put anything in `build=` or your source
  files that you wouldn't want run unreviewed on a stranger's machine.
  Keep build steps to the obvious, expected thing (`npm install`, `make`,
  `cargo build`) so a reader can tell at a glance what it does.
- **As an installer:** `tlib install` on an unfamiliar repo is
  equivalent to `curl | sh` — read the `info.xml` (and the source it
  points at) first, the same way you'd want someone to look at your own
  repo before running `tlib install` on it.

---

## 7. Common compliance failures, decoded

| Error you see | What it means | Fix |
|---|---|---|
| `GitHub repo or branch not found` | Repo is private, misspelled, or on a different default branch than `main` | Make it public; double check spelling; tell installers to use a branch-qualified URL if not `main` |
| `<tool> is required for info.xml requirement` | Something in `<requires>` isn't on the installer's `PATH` | That's expected/by design — just make sure you're not requiring tools you don't actually need |
| `command '<name>' needs source, build, or output` | A `<command>` has none of the three | Add one |
| `duplicate command names: <name>` | Two `<command>` elements share a name | Rename one |
| `command #N has invalid or missing name` | Name has illegal characters, or couldn't be derived from `source` | Use only `A-Za-z0-9._+-`, or set `name=` explicitly |
| `... must be a relative path inside the repo` | A `source`/`output`/`sources` path is absolute or contains `..` | Use a path relative to the repo root, no `../` |
| `declared output for command '<name>' does not exist` | Your `output=` points at a file that isn't actually there after the build | Check the path, check your build actually produces it, check it isn't `.gitignore`d |
| `command '<name>' did not produce an executable; add output=...` | `tlib` searched the default candidate paths and found nothing | Set `output=` explicitly |
| `<lang> is required for <lang> command '<name>'` | Compiler/interpreter for that language isn't installed | List it in `<requires>` so this surfaces earlier, as a warning instead of a hard failure |
| Works with `tlib local`, fails with `tlib install Owner/Repo` | The version on GitHub differs from your working copy — usually uncommitted changes, or you're testing the wrong branch | Commit and push everything, then re-test the real install command |
| Works for you, fails for a friend | Almost always a missing `<requires>` entry — something's on your `PATH` (from other dev tools you have installed) that isn't on theirs | Run `tlib doctor` on a clean machine if you can, or just double-check every tool your `build=`/`source` steps actually touch is declared |
