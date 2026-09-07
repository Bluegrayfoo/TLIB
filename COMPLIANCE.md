# Making a repo compliant with `tlib`

This is the full checklist and reference for getting a GitHub repo to
install cleanly with `tlib install`. Everything here is derived directly
from `ZSH.zsh` — if your repo satisfies these rules, `tlib install` will
work; if it doesn't, this doc tells you exactly which check fails and why.
Every rule below has a concrete example showing what passes and what
fails it.

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

- [ ] **The repo is public.** `tlib install Owner/Repo` downloads
      `https://github.com/Owner/Repo/archive/refs/heads/main.tar.gz` with
      an unauthenticated `curl` request — no login, no token. If `Repo` is
      private (or the owner/name is misspelled), GitHub returns HTTP 404
      and `tlib` reports:
      ```
      GitHub repo or branch not found: Owner/Repo on branch 'main'.
      Check the spelling, make sure the repo is public, and make sure the branch is named 'main'.
      ```
      **Fix:** make the repo public in its GitHub settings, or double-check
      the spelling of the owner/repo name.

- [ ] **The branch you're installing from is actually named what you
      think.** `tlib install Owner/Repo` (bare form) always assumes
      `main`:
      ```bash
      tlib install Owner/Repo
      # → tries https://github.com/Owner/Repo/archive/refs/heads/main.tar.gz
      ```
      If your repo's default branch is `master` (or anything else), that
      404s the same way a missing repo does. **Fix:** either rename your
      default branch to `main`, or tell installers to use a
      branch-qualified `raw.githubusercontent.com` URL instead:
      ```bash
      tlib install https://raw.githubusercontent.com/Owner/Repo/master/
      ```

- [ ] **`info.xml` (or `make.sh` + `src/`) lives at the repo root** — not
      in a subdirectory. Good layout:
      ```
      my-repo/
      ├── info.xml          ← tlib looks exactly here
      └── my-tool.sh
      ```
      This does **not** work — `tlib` never looks inside subdirectories
      for `info.xml`:
      ```
      my-repo/
      └── config/
          └── info.xml      ← tlib will never find this
      ```

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
`<requires>`/`<tool>` elements anywhere in the file. So this flatter
version, with no `<package>` at all, installs identically to the example
above:

```xml
<tlib version="1">
  <requires>
    <tool name="node"/>
  </requires>
  <commands>
    <command name="my-tool" source="my-tool.js" language="node"/>
  </commands>
</tlib>
```

(Still, use the `<package>`-wrapped form in your own repos — it's the
convention every real repo follows, and it's what a reader expects.)

There's currently no version-compatibility mechanism at all: changing
`version="1.0.0"` to `version="99.0.0"` changes nothing about how the
file installs — `tlib` doesn't read it. Likewise, a
`<platforms><platform name="macos"/></platforms>` block (you may see this
in some repos, like this line from a real one:
`<platforms><platform name="macos"/></platforms>`) is **silently
ignored** — `tlib` has no OS-gating logic, so it does not stop someone on
a different platform from attempting an install that may then fail on
missing tools.

### 2.1 `<requires>`

- Lists tools that must already be on the installing machine's `PATH`.
  Checked with a plain `command -v`, **before** anything else in the file
  is processed. Both of these forms are equivalent:
  ```xml
  <tool name="node"/>
  ```
  ```xml
  <tool>node</tool>
  ```
- Accepts `<tool>`, `<require>`, or `<dependency>` as the tag name — these
  three are also equivalent:
  ```xml
  <tool name="git"/>
  <require name="git"/>
  <dependency name="git"/>
  ```
  and they work anywhere in the file, not just inside a `<requires>`
  wrapper (the wrapper, like `<package>`, is just for readability).
- If a listed tool is missing, the whole install aborts immediately —
  nothing gets installed, even other unrelated commands in the same file:
  ```
  tlib info.xml: rustc is required for info.xml requirement
  ```
- **Compliance tip:** only list tools your commands' `build=` steps or
  runtime actually need. A repo that only ships a shell script shouldn't
  have `<tool name="python3"/>` in it — every install of your repo pays
  that cost for nothing.

### 2.2 `<command>` — required fields

Each command needs:

- **A name**: `name=` (or `id=`). If omitted, it's derived from `source`'s
  filename without extension:
  ```xml
  <command source="my-tool.sh" language="shell"/>
  <!-- name becomes "my-tool" automatically -->
  ```
  The name must match `^[A-Za-z0-9._+-]+$` — no slashes, no spaces:
  ```xml
  <command name="my-tool" .../>       <!-- OK -->
  <command name="my tool" .../>       <!-- FAILS: contains a space -->
  <command name="my/tool" .../>       <!-- FAILS: contains a slash -->
  ```
  Failing case produces: `command #N has invalid or missing name`.

- **Exactly one of `source`, `build`, or `output`.** This is invalid —
  none of the three are present:
  ```xml
  <command name="my-tool"/>
  <!-- FAILS: command 'my-tool' needs source, build, or output -->
  ```
  This is valid — `output` alone is enough:
  ```xml
  <command name="my-tool" output="bin/my-tool"/>
  ```

- **A unique name.** This is invalid — two commands, same name:
  ```xml
  <commands>
    <command name="my-tool" output="bin/my-tool"/>
    <command name="my-tool" output="bin/my-tool-gui"/>
  </commands>
  <!-- FAILS: duplicate command names: my-tool -->
  ```

A repo can declare as many `<command>` elements as it wants (see the
multi-command example in section 5) — each one becomes a separate
installed command, and there's no requirement that a command's name
match the repo name.

### 2.3 Picking how a command gets built

**`output` only (no `source`, no `build`)** — the file is already built
and checked into the repo (e.g. a prebuilt binary or a hand-written
wrapper script under `bin/`). Used as-is.

```xml
<command name="my-tool" output="bin/my-tool"/>
```

- The path must exist in the repo and must stay **inside** the repo.
  This fails — it points outside the repo:
  ```xml
  <command name="my-tool" output="../outside-the-repo/my-tool"/>
  <!-- FAILS: output for command 'my-tool' must be a relative path inside the repo -->
  ```
- If the referenced file doesn't exist in the downloaded repo at all:
  ```
  declared output for command 'my-tool' does not exist: bin/my-tool
  ```
- **Compliance tip:** the file must actually be committed to the repo —
  a `.gitignore` line like `bin/` (very common for build output
  directories) will silently exclude it, and installers get the "does
  not exist" error with no obvious cause:
  ```
  # .gitignore
  bin/          ← if this line exists, bin/my-tool never reaches GitHub
  ```
  Double check with a fresh clone, not just your working copy.

**`build` (with or without `output`)** — runs a shell command in the repo
root first (e.g. `npm install`, `make`, `cargo build --release`), then
locates the result.

```xml
<command name="my-tool" build="npm install" output="bin/my-tool"/>
```

`output` is optional here — if you omit it, `tlib` searches, in order:
`<repo>/<name>`, `<repo>/build/<name>`, `<repo>/dist/<name>`,
`<repo>/bin/<name>`, `<repo>/.build/release/<name>`,
`<repo>/.build/debug/<name>`, then its own build scratch directory:

```xml
<command name="my-tool" build="make"/>
<!-- works with no output= ONLY IF `make` produces ./my-tool, ./build/my-tool,
     ./dist/my-tool, or ./bin/my-tool in the repo root -->
```

**Compliance tip:** if your build output doesn't land in one of those
exact paths under that exact name, always set `output=` explicitly —
don't rely on the search order.

If the build command itself fails (non-zero exit), install aborts:
```
command failed with exit 127: npm install
```
(exit 127 here would mean `npm` itself wasn't found — see the trust note
in section 6 about not assuming your dev machine's tools are present.)

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

A couple of rows that don't get their own worked example in section 5:

```xml
<!-- explicit framework instead of auto-detection -->
<command name="my-app" source="AppDelegate.m" language="objc" frameworks="AppKit UIKit"/>

<!-- Swift with extra files compiled together -->
<command name="my-app" source="main.swift" language="swift" sources="Helper.swift Model.swift"/>

<!-- force a specific interpreter instead of the language default -->
<command name="my-tool" source="my-tool.py" language="python" interpreter="python3.11"/>

<!-- extra flags passed straight to the compiler -->
<command name="my-tool" source="my-tool.c" language="c" args="-O2 -Wall"/>
```

Extension-to-language auto-detection (used only when `language=` is
omitted): `.c`→c, `.cc/.cpp/.cxx`→cpp, `.m`→objc, `.swift`→swift,
`.py`→python, `.sh/.zsh/.bash`→shell, `.js/.mjs`→node, `.rb`→ruby,
`.pl`→perl, `.php`→php, `.lua`→lua, `.go`→go, `.rs`→rust. So these two
lines behave identically:

```xml
<command name="my-tool" source="my-tool.py"/>
<command name="my-tool" source="my-tool.py" language="python"/>
```

**Compliance tip:** if you need a compiled/interpreted language, list the
matching tool in `<requires>` so `tlib doctor` warns installers *before*
they hit a failed build:

```xml
<requires>
  <tool name="rustc"/>
</requires>
<commands>
  <command name="my-tool" source="main.rs" language="rust"/>
</commands>
```

Without the `<requires>` entry, a missing `rustc` fails later, mid-build,
with: `rust is required for rust command 'my-tool'` — same underlying
problem, worse timing.

**Compliance tip:** the interpreter-wrapper shim execs your source file
**at its path inside the persistent download cache**
(`~/.tlib/repos/<owner>/<repo>/<branch>/...`), not a copy of it
elsewhere. If your script does relative-path file I/O based on its own
location (like `Path(__file__).parent / "config.json"` in Python), that
still works — it resolves relative to the cache location — but don't
assume it runs from your repo clone's path.

### 2.4 Field name aliases

Most fields accept more than one attribute name — pick whichever reads
best. These two commands are exactly equivalent:

```xml
<command name="my-tool" source="my-tool.js" language="node"/>
<command id="my-tool" src="my-tool.js" lang="node"/>
```

Full alias table:

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

Example layout:

```
my-repo/
├── make.sh              ← runs first, from the repo root
└── src/
    ├── my-tool.sh        ← becomes command "my-tool"
    └── my-helper.py      ← becomes command "my-helper"
```

A minimal `make.sh` that does nothing (fine — it's only required to
exist and exit successfully; `tlib` compiles `src/*` itself if `make.sh`
doesn't produce matching executables):

```bash
#!/bin/sh
echo "nothing to build"
```

- [ ] A `make.sh` at the repo root — runs first, from the repo root.
- [ ] One or more files directly under `src/` — command name = filename
      without extension (`src/my-tool.sh` → command `my-tool`).
- [ ] For each `src/` file, if `make.sh` already produced a matching
      executable (checked at `<repo>/<name>`, `build/<name>`,
      `dist/<name>`, `bin/<name>`, `.build/release/<name>`, or
      `.build/debug/<name>` — same search as `output` resolution above),
      that's used. Otherwise `tlib` compiles it itself, using this
      **smaller** language set: `c`, `cc`/`cpp`/`cxx`, `m`, `swift`,
      `sh`/`zsh`/`bash`, `py`, `js`/`mjs`, `rb`, `pl`, `php`, `lua`. No
      `go`, `rust`, `copy`/`binary`/`prebuilt`, and no custom
      `interpreter=` override — if you need any of those, use `info.xml`
      instead.
- [ ] At least one command must actually get installed, or the whole
      install fails with `no source files found in src/` (e.g. an empty
      `src/` directory, or one containing only files `tlib` can't
      compile).

---

## 4. Test before you publish

```bash
tlib local /path/to/your/repo
```

Runs the exact same `info.xml`/legacy install logic against a local
directory — no download, no need to push first. For example, while
actively editing:

```bash
cd ~/projects/my-tool
tlib local .
my-tool --help          # confirm it actually works
tlib uninstall local/my-tool
```

Fix everything `tlib local` flags before you push and tell anyone to
`tlib install` your repo.

```bash
tlib doctor
```

Shows what's on *your* machine — useful for confirming which optional
compiler toolchains you personally have, so you know which of your
`<requires>` entries you can actually test locally.

**A local test only proves the file *your working copy* has works.** It
does not prove the version on GitHub does. Before telling anyone to
install your repo, also do the real thing at least once:

```bash
cd /tmp                              # anywhere that ISN'T your repo clone
tlib install YourUsername/your-repo
your-tool --help
tlib uninstall YourUsername/your-repo
```

That way you're testing exactly what a stranger would get — including
whatever's actually committed and pushed, not files that only exist in
your working copy.

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

Concretely, both of these run with zero prompts or warnings the moment
someone runs `tlib install` on your repo:

```xml
<command name="my-tool" build="npm install" output="bin/my-tool"/>
<!-- expected: runs npm install, an installer would recognize this at a glance -->

<command name="my-tool" build="curl https://example.com/x | sh" output="bin/my-tool"/>
<!-- also runs, exactly as written, with the same lack of confirmation —
     don't ship something like this without making very clear what it does -->
```

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
| `command '<name>' needs source, build, or output` | A `<command>` has none of the three | Add one — see the 2.2 example |
| `duplicate command names: <name>` | Two `<command>` elements share a name | Rename one — see the 2.2 example |
| `command #N has invalid or missing name` | Name has illegal characters, or couldn't be derived from `source` | Use only `A-Za-z0-9._+-`, or set `name=` explicitly |
| `... must be a relative path inside the repo` | A `source`/`output`/`sources` path is absolute or contains `..` | Use a path relative to the repo root, no `../` — see the 2.3 example |
| `declared output for command '<name>' does not exist` | Your `output=` points at a file that isn't actually there after the build | Check the path, check your build actually produces it, check it isn't `.gitignore`d |
| `command '<name>' did not produce an executable; add output=...` | `tlib` searched the default candidate paths and found nothing | Set `output=` explicitly |
| `<lang> is required for <lang> command '<name>'` | Compiler/interpreter for that language isn't installed | List it in `<requires>` so this surfaces earlier, as a warning instead of a hard failure |
| Works with `tlib local`, fails with `tlib install Owner/Repo` | The version on GitHub differs from your working copy — usually uncommitted changes, or you're testing the wrong branch | Commit and push everything, then re-test the real install command |
| Works for you, fails for a friend | Almost always a missing `<requires>` entry — something's on your `PATH` (from other dev tools you have installed) that isn't on theirs | Run `tlib doctor` on a clean machine if you can, or just double-check every tool your `build=`/`source` steps actually touch is declared |
