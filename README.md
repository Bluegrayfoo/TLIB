# TLIB

A single zsh script that installs small GitHub-hosted "command" repos as
executables on your `PATH`. Point it at a repo and it downloads, builds
if needed, and drops the command(s) into `~/cmds`.

## Setup

```bash
git clone https://github.com/BlueGrayFoo/TLIB.git
cd TLIB
chmod +x ZSH.zsh tlibUpdater
ln -s "$(pwd)/ZSH.zsh" /usr/local/bin/tlib
ln -s "$(pwd)/tlibUpdater" /usr/local/bin/tlibUpdater
```

`tlib` and `tlibUpdater` both are installed with that command. (`zsh`,
`curl`, `tar`, `python3` are all either needs, and macOS already has them.)

```bash
tlibUpdater update
```

pulls the latest `ZSH.zsh` from this repo and overwrites your installed
`tlib` with it (backing up the old one first as `<path>.bak`), or says
it's already up to date if nothing changed.

<details>
<summary>Only if `tlib doctor` warns about a missing compiler</summary>

Some repos build C/C++/Objective-C/Swift/Go/Rust source, which needs
`clang`/`clang++`/`swiftc`/`go`/`rustc`. Most repos don't need this —
`tlib doctor` just warns, it doesn't block installs without them.

```bash
xcode-select --install    # clang, clang++, swiftc
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y   # rustc

GOVER=$(curl -s 'https://go.dev/VERSION?m=text' | head -1)
ARCH=$(uname -m); [ "$ARCH" = "x86_64" ] && ARCH=amd64
curl -LO "https://go.dev/dl/$GOVER.darwin-$ARCH.tar.gz"
sudo tar -C /usr/local -xzf "$GOVER.darwin-$ARCH.tar.gz"
sudo ln -sf /usr/local/go/bin/go /usr/local/bin/go
rm -f "$GOVER.darwin-$ARCH.tar.gz"
```

(Go uses the tarball, not the `.pkg` installer — the `.pkg` refuses to run
on macOS versions older than 13.)

</details>

## Usage

```bash
tlib install RepoName          # or Owner/RepoName, or a github.com URL
tlib uninstall RepoName
tlib doctor                    # check dependencies
```

## Publishing your own repo

See [COMPLIANCE.md](COMPLIANCE.md) for the full checklist and every
possible error message decoded. Short version: add an `info.xml` to the
repo root:

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

`<requires>` lists tools that must already be on `PATH`. Each `<command>`
needs a `name` and a `source` file — tlib picks how to run it from the
file extension (or an explicit `language=`): shell scripts are copied
as-is, Python/Node/Ruby/etc. get wrapped in a shim that execs the right
interpreter, and C/C++/Objective-C/Swift/Go/Rust get compiled. A command
can also use `build="some shell command"` instead of `source`, if it
needs a build step first.

<details>
<summary>Full reference (env vars, exact info.xml spec, legacy repo shape)</summary>

### Environment variables

| Variable | Default | Purpose |
|---|---|---|
| `TLIB_INSTALL_DIR` | `~/cmds` | Where installed commands are copied |
| `TLIB_CACHE_DIR` | `~/.tlib` | Where repo downloads and install manifests live |
| `TLIB_DEFAULT_OWNER` | `Bluegrayfoo` | GitHub owner assumed when `install` is given a bare repo name |
| `TLIB_COLOR` | `always` | `never` disables colored progress output |

### All `install` forms

```
tlib install RepoName
tlib install Owner/RepoName
tlib install https://github.com/Owner/RepoName
tlib install https://raw.githubusercontent.com/Owner/RepoName/branch/
tlib install-owner Owner RepoName    # same as install Owner/RepoName
tlib local /path/to/repo             # install from a local directory, no download
tlib --version
```

### How install works

`tlib install <spec>` downloads the repo's tarball into
`$TLIB_CACHE_DIR/repos/<owner>/<repo>/<branch>`, installs from `info.xml`
if present (else falls back to a legacy `make.sh` + `src/*` shape), copies
each resulting command into `$TLIB_INSTALL_DIR`, and writes a manifest to
`$TLIB_CACHE_DIR/installed/<owner>__<repo>` listing what it installed.
`tlib uninstall` just reads that manifest back and deletes those files.

Only public GitHub repos are supported — downloads use GitHub's
unauthenticated archive endpoint.

### `info.xml`, in full

Each `<command>` needs a `name` (or `id`; derived from `source`'s filename
if omitted) and one of `source`, `build`, or `output`:

- **`build`** — runs a shell command in the repo root, then looks for the
  resulting executable at `output` (if given) or by searching
  `<repo>/<name>`, `build/`, `dist/`, `bin/`, `.build/release/`,
  `.build/debug/`.
- **`output`** (no `source`) — the file's already built; used as-is.
- **`source`** — dispatched by `language` (or file extension):
  `c`/`cpp`/`c++` → clang/clang++; `objc`/`m` → clang with a framework
  from `frameworks` or auto-detected; `swift` → swiftc (extra files via
  `sources`); `shell`/`sh`/`bash`/`zsh` → copied as-is; `python`/`node`/
  `ruby`/`perl`/`php`/`lua` → wrapped in a shim exec'ing that interpreter
  (override with `interpreter`); `go` → `go build`; `rust` → `rustc`;
  `copy`/`binary`/`prebuilt` → copied as-is.

`args` passes extra flags to the compiler/build step. Paths in `source`,
`output`, and `sources` must stay inside the repo. Command names must be
unique and contain only alphanumerics, `.`, `_`, `+`, `-`. Most fields
accept a couple of aliases (e.g. `source`/`src`/`file`/`path`).

### Legacy repo shape

Used when there's no `info.xml`: a `make.sh` at the repo root, plus one or
more files under `src/` (command name = filename without extension).
`make.sh` runs first; if it didn't already produce a matching executable,
tlib compiles the source itself (a smaller language set than `info.xml`:
c/cc/cpp/cxx, m, swift, sh/zsh/bash, py, js/mjs, rb, pl, php, lua).

</details>
