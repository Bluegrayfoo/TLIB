#!/bin/zsh
set -u

INSTALL_DIR="${TLIB_INSTALL_DIR:-$HOME/cmds}"
CACHE_DIR="${TLIB_CACHE_DIR:-$HOME/.tlib}"
MANIFEST_DIR="$CACHE_DIR/installed"
DEFAULT_OWNER="${TLIB_DEFAULT_OWNER:-Bluegrayfoo}"

usage() {
  cat <<'USAGE'
tlib - install small GitHub command repos

Usage:
  tlib install RepoName
  tlib install Bluegrayfoo/RepoName
  tlib install https://github.com/Bluegrayfoo/RepoName
  tlib install https://raw.githubusercontent.com/Bluegrayfoo/RepoName/main/
  tlib install-owner Bluegrayfoo RepoName
  tlib uninstall RepoName
  tlib doctor
  tlib local /path/to/repo

Preferred repo shape:
  info.xml

Legacy repo shape:
  make.sh
  src/cmda.c
  src/cmdb.c

When info.xml exists, tlib obeys it. Without info.xml, tlib keeps the
legacy make.sh + src/* installer behavior.
USAGE
}

use_color() {
  [ "${TLIB_COLOR:-always}" != "never" ] || return 1
  if [ "${TLIB_COLOR:-always}" = "always" ]; then return 0; fi
  [ "${NO_COLOR:-}" = "" ] || return 1
  [ -t 1 ]
}

colorize() {
  local code="$1"
  local text="$2"
  if use_color; then
    printf '\033[%sm%s\033[0m' "$code" "$text"
  else
    printf '%s' "$text"
  fi
}

progress_diamond() { colorize "38;5;43" "◇"; }
progress_pipe() { colorize "38;5;27" "│"; }
progress_ok() { colorize "38;5;48" "✓"; }
progress_fail() { colorize "38;5;196" "✗"; }
progress_spin() { colorize "38;5;87" "$1"; }
progress_label() { colorize "38;5;117" "$1"; }
progress_done() { colorize "38;5;121" "$1"; }
progress_final() { colorize "38;5;84" "$1"; }
progress_error() { colorize "38;5;203" "$1"; }
progress_connector() { colorize "38;5;27" "$1"; }

first_error_line() {
  local log="$1"
  local line
  if [ -s "$log" ]; then
    line="$(sed -n '/[^[:space:]]/ { s/^[[:space:]]*//; p; q; }' "$log")"
    [ -n "$line" ] && { print -- "$line"; return 0; }
  fi
  print -- "Unknown error."
}

print_error_tail() {
  local log="$1"
  local first=1
  local line
  [ -s "$log" ] || return 0
  while IFS= read -r line; do
    [ -n "${line//[[:space:]]/}" ] || continue
    if [ "$first" -eq 1 ]; then
      first=0
      continue
    fi
    printf '   %s\n' "$line" >&2
  done < "$log"
}

run_logged_command() {
  local log="$1"
  shift
  "$@" >"$log" 2>&1
}

run_step() {
  local label="$1"
  local done="$2"
  local fail="$3"
  shift 3

  local log="${TMPDIR:-/tmp}/tlib-command-$$-$RANDOM.log"
  local -a frames
  frames=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
  local i=1
  local pid
  local result_status=0

  if [ -n "${ZSH_VERSION:-}" ]; then
    setopt localoptions nobgnice nomonitor
  fi

  printf '%s\n' "$(progress_pipe)"
  (
    run_logged_command "$log" "$@"
  ) &
  pid=$!

  while kill -0 "$pid" 2>/dev/null; do
    printf '\r\033[2K%s    %s   %s...' "$(progress_diamond)" "$(progress_spin "${frames[$i]}")" "$(progress_label "$label")"
    i=$((i + 1))
    if [ "$i" -gt "${#frames[@]}" ]; then i=1; fi
    sleep 0.08
  done

  wait "$pid"
  result_status=$?
  printf '\r\033[2K'

  if [ "$result_status" -eq 0 ]; then
    printf '%s    %s   %s\n' "$(progress_diamond)" "$(progress_ok)" "$(progress_done "$done")"
  else
    local detail="$(first_error_line "$log")"
    printf '%s    %s   %s\n' "$(progress_connector '├─')" "$(progress_fail)" "$(progress_error "$fail")" >&2
    printf '%s\n' "$(progress_pipe)" >&2
    printf '%s    %s  %s\n' "$(progress_connector '└─')" "$(progress_error "Error:")" "$(progress_error "$detail")" >&2
    print_error_tail "$log"
  fi

  rm -f "$log"
  return "$result_status"
}

finish_progress() {
  local message="${1:-Done.}"
  printf '%s\n' "$(progress_pipe)"
  printf '%s    %s\n' "$(progress_connector '└─')" "$(progress_final "$message")"
}

die() {
  print -u2 -- "tlib: $*"
  exit 1
}

have() {
  command -v "$1" >/dev/null 2>&1
}

repo_parts_from_spec() {
  local spec="$1"
  local cleaned="$spec"

  cleaned="${cleaned#https://github.com/}"
  cleaned="${cleaned#http://github.com/}"
  cleaned="${cleaned#git@github.com:}"
  cleaned="${cleaned#https://raw.githubusercontent.com/}"
  cleaned="${cleaned#http://raw.githubusercontent.com/}"
  cleaned="${cleaned%.git}"
  cleaned="${cleaned%/}"

  local owner="${cleaned%%/*}"
  local rest="${cleaned#*/}"
  local repo="${rest%%/*}"

  if [ "$owner" = "$cleaned" ]; then
    owner="$DEFAULT_OWNER"
    repo="$cleaned"
    rest="$repo"
  fi
  local branch="main"

  if [[ "$spec" == *raw.githubusercontent.com* ]]; then
    local after_repo="${rest#*/}"
    if [ "$after_repo" != "$rest" ] && [ -n "$after_repo" ]; then
      branch="${after_repo%%/*}"
    fi
  fi

  [ -n "$owner" ] && [ -n "$repo" ] || return 1
  print -- "$owner $repo $branch"
}

download_repo() {
  local owner="$1"
  local repo="$2"
  local branch="$3"
  local dest="$4"
  local url="https://github.com/${owner}/${repo}/archive/refs/heads/${branch}.tar.gz"
  local archive="$dest.tar.gz"
  local http_code

  rm -rf "$dest" "$archive"
  mkdir -p "$dest"

  have curl || { print -u2 -- "curl is required to download GitHub repos"; return 1; }

  http_code="$(curl -L -s -w '%{http_code}' "$url" -o "$archive")"
  if [ "$http_code" != "200" ]; then
    rm -f "$archive"
    case "$http_code" in
      404)
        print -u2 -- "GitHub repo or branch not found: $owner/$repo on branch '$branch'."
        print -u2 -- "Check the spelling, make sure the repo is public, and make sure the branch is named '$branch'."
        ;;
      000)
        print -u2 -- "Could not connect to GitHub. Check your internet connection."
        ;;
      *)
        print -u2 -- "GitHub returned HTTP $http_code while downloading $owner/$repo."
        ;;
    esac
    print -u2 -- "URL: $url"
    return 1
  fi

  tar -xzf "$archive" -C "$dest" --strip-components=1 || {
    rm -f "$archive"
    print -u2 -- "Downloaded $owner/$repo, but the archive could not be unpacked."
    return 1
  }
  rm -f "$archive"
}

command_name_for_source() {
  local source="$1"
  local base="${source:t}"
  print -- "${base%.*}"
}

compile_one_source() {
  local source="$1"
  local out="$2"
  local ext="${source:e:l}"

  case "$ext" in
    c)
      have clang || die "clang is required to compile C files"
      clang "$source" -o "$out"
      ;;
    cc|cpp|cxx)
      have clang++ || die "clang++ is required to compile C++ files"
      clang++ "$source" -o "$out"
      ;;
    m)
      have clang || die "clang is required to compile Objective-C files"
      if grep -q "AppKit\|Cocoa" "$source"; then
        clang -fobjc-arc -framework AppKit "$source" -o "$out"
      else
        clang -fobjc-arc -framework Foundation "$source" -o "$out"
      fi
      ;;
    swift)
      have swiftc || die "swiftc is required to compile Swift files"
      swiftc "$source" -o "$out"
      ;;
    sh|zsh|bash)
      cp "$source" "$out"
      chmod +x "$out"
      ;;
    py)
      make_interpreter_wrapper python3 "$source" "$out"
      ;;
    js|mjs)
      make_interpreter_wrapper node "$source" "$out"
      ;;
    rb)
      make_interpreter_wrapper ruby "$source" "$out"
      ;;
    pl)
      make_interpreter_wrapper perl "$source" "$out"
      ;;
    php)
      make_interpreter_wrapper php "$source" "$out"
      ;;
    lua)
      make_interpreter_wrapper lua "$source" "$out"
      ;;
    *)
      return 2
      ;;
  esac
}

make_interpreter_wrapper() {
  local interpreter="$1"
  local source="$2"
  local out="$3"
  have "$interpreter" || die "$interpreter is required to run $source"
  {
    print -- "#!/bin/sh"
    printf 'exec %s %s "$@"\n' "$(printf '%q' "$interpreter")" "$(printf '%q' "$source")"
  } > "$out"
  chmod +x "$out"
}

find_built_command() {
  local repo_dir="$1"
  local name="$2"
  local candidate
  for candidate in \
    "$repo_dir/$name" \
    "$repo_dir/build/$name" \
    "$repo_dir/dist/$name" \
    "$repo_dir/bin/$name" \
    "$repo_dir/.build/release/$name" \
    "$repo_dir/.build/debug/$name"; do
    if [ -f "$candidate" ] && [ -x "$candidate" ]; then
      print -- "$candidate"
      return 0
    fi
  done
  return 1
}

install_command_file() {
  local file="$1"
  local name="$2"
  mkdir -p "$INSTALL_DIR"
  cp "$file" "$INSTALL_DIR/$name"
  chmod +x "$INSTALL_DIR/$name"
}

module_key_from_parts() {
  local owner="$1"
  local repo="$2"
  print -- "$owner/$repo"
}

manifest_path_for_key() {
  local key="$1"
  local safe="${key//\//__}"
  print -- "$MANIFEST_DIR/$safe"
}

write_manifest() {
  local key="$1"
  shift
  mkdir -p "$MANIFEST_DIR"
  local manifest="$(manifest_path_for_key "$key")"
  {
    print -- "module=$key"
    print -- "installed_at=$(date '+%Y-%m-%d %H:%M:%S')"
    print -- "install_dir=$INSTALL_DIR"
    print -- "commands=$*"
  } > "$manifest"
}

install_info_xml() {
  local repo_dir="$1"
  local module_key="$2"
  have python3 || die "python3 is required to parse info.xml"
  {
    run_step "Installing from info.xml" "Installed info.xml commands" "info.xml install failed" \
      python3 - "$repo_dir" "$INSTALL_DIR" "$MANIFEST_DIR" "$module_key"
  } <<'PY' || return 1
import os
import shlex
import shutil
import stat
import subprocess
import sys
import textwrap
import xml.etree.ElementTree as ET
from pathlib import Path

repo = Path(sys.argv[1]).resolve()
install_dir = Path(sys.argv[2]).expanduser().resolve()
manifest_dir = Path(sys.argv[3]).expanduser().resolve()
module_key = sys.argv[4]
info_path = repo / "info.xml"
build_dir = repo / ".tlib-build"

LANG_BY_EXT = {
    ".c": "c",
    ".cc": "cpp",
    ".cpp": "cpp",
    ".cxx": "cpp",
    ".m": "objc",
    ".swift": "swift",
    ".py": "python",
    ".sh": "shell",
    ".zsh": "zsh",
    ".bash": "bash",
    ".js": "node",
    ".mjs": "node",
    ".rb": "ruby",
    ".pl": "perl",
    ".php": "php",
    ".lua": "lua",
    ".go": "go",
    ".rs": "rust",
}

INTERPRETERS = {
    "python": "python3",
    "python3": "python3",
    "node": "node",
    "javascript": "node",
    "js": "node",
    "ruby": "ruby",
    "perl": "perl",
    "php": "php",
    "lua": "lua",
}

def fail(message: str) -> None:
    raise SystemExit(f"tlib info.xml: {message}")

def tag(elem) -> str:
    return elem.tag.rsplit("}", 1)[-1].lower()

def first_text(elem, *names: str) -> str:
    names = {name.lower() for name in names}
    for child in elem:
        if tag(child) in names and child.text:
            return child.text.strip()
    return ""

def value(elem, *names: str) -> str:
    for name in names:
        for key in (name, name.replace("-", "_"), name.replace("_", "-")):
            if key in elem.attrib and elem.attrib[key].strip():
                return elem.attrib[key].strip()
    return first_text(elem, *names)

def bool_value(text: str, default: bool = False) -> bool:
    if not text:
        return default
    return text.strip().lower() in {"1", "true", "yes", "on"}

def safe_name(name: str) -> bool:
    if not name or "/" in name or name in {".", ".."}:
        return False
    return all(ch.isalnum() or ch in "._+-" for ch in name)

def rel_path(text: str, field: str) -> Path:
    if not text:
        fail(f"missing {field}")
    p = Path(text)
    if p.is_absolute() or ".." in p.parts:
        fail(f"{field} must be a relative path inside the repo: {text}")
    return repo / p

def run(command, cwd=repo):
    if isinstance(command, str):
        command = ["sh", "-c", command]
    try:
        subprocess.run(command, cwd=cwd, check=True)
    except FileNotFoundError:
        fail(f"required tool not found while running: {command[0]}")
    except subprocess.CalledProcessError as exc:
        fail(f"command failed with exit {exc.returncode}: {' '.join(map(str, command))}")

def need(tool: str, why: str) -> None:
    if shutil.which(tool) is None:
        fail(f"{tool} is required for {why}")

def shell_words(text: str):
    return shlex.split(text) if text else []

def compile_source(command):
    name = command["name"]
    source = command.get("source", "")
    source_path = rel_path(source, f"source for command '{name}'")
    if not source_path.is_file():
        fail(f"source for command '{name}' does not exist: {source}")

    lang = (command.get("language") or LANG_BY_EXT.get(source_path.suffix.lower()) or "").lower()
    out = build_dir / name
    build_dir.mkdir(parents=True, exist_ok=True)
    extra = shell_words(command.get("args", ""))

    if lang in {"c"}:
        need("clang", f"C command '{name}'")
        run(["clang", str(source_path), "-o", str(out), *extra])
    elif lang in {"cpp", "c++"}:
        need("clang++", f"C++ command '{name}'")
        run(["clang++", str(source_path), "-o", str(out), *extra])
    elif lang in {"objc", "objective-c", "m"}:
        need("clang", f"Objective-C command '{name}'")
        frameworks = shell_words(command.get("frameworks", ""))
        if not frameworks:
            frameworks = ["AppKit" if "AppKit" in source_path.read_text(errors="ignore") or "Cocoa" in source_path.read_text(errors="ignore") else "Foundation"]
        args = ["clang", "-fobjc-arc", str(source_path)]
        for fw in frameworks:
            args.extend(["-framework", fw])
        run([*args, "-o", str(out), *extra])
    elif lang == "swift":
        need("swiftc", f"Swift command '{name}'")
        sources = [str(source_path)]
        sources_text = command.get("sources", "")
        if sources_text:
            sources = [str(rel_path(part, f"sources for command '{name}'")) for part in shell_words(sources_text)]
        run(["swiftc", *sources, "-o", str(out), *extra])
    elif lang in {"shell", "sh", "bash", "zsh"}:
        shutil.copy2(source_path, out)
        out.chmod(out.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    elif lang in INTERPRETERS:
        interpreter = command.get("interpreter") or INTERPRETERS[lang]
        need(interpreter, f"{lang} command '{name}'")
        out.write_text(f"#!/bin/sh\nexec {shlex.quote(interpreter)} {shlex.quote(str(source_path))} \"$@\"\n")
        out.chmod(0o755)
    elif lang == "go":
        need("go", f"Go command '{name}'")
        run(["go", "build", "-o", str(out), str(source_path), *extra])
    elif lang in {"rust", "rs"}:
        need("rustc", f"Rust command '{name}'")
        run(["rustc", str(source_path), "-o", str(out), *extra])
    elif lang in {"copy", "binary", "prebuilt"}:
        shutil.copy2(source_path, out)
        out.chmod(out.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    else:
        fail(f"command '{name}' has unsupported language '{lang or 'unknown'}'")

    return out

def find_output(command):
    name = command["name"]
    if command.get("output"):
        output = rel_path(command["output"], f"output for command '{name}'")
        if not output.is_file():
            fail(f"declared output for command '{name}' does not exist: {command['output']}")
        return output
    for candidate in (
        repo / name,
        repo / "build" / name,
        repo / "dist" / name,
        repo / "bin" / name,
        repo / ".build" / "release" / name,
        repo / ".build" / "debug" / name,
        build_dir / name,
    ):
        if candidate.is_file():
            return candidate
    fail(f"command '{name}' did not produce an executable; add output=\"path/to/{name}\"")

def command_elements(root):
    elems = []
    for elem in root.iter():
        if tag(elem) == "command":
            elems.append(elem)
    return elems

def parse_commands(root):
    commands = []
    for index, elem in enumerate(command_elements(root), 1):
        name = value(elem, "name", "id")
        source = value(elem, "source", "src", "file", "path")
        if not name and source:
            name = Path(source).stem
        if not safe_name(name):
            fail(f"command #{index} has invalid or missing name")
        command = {
            "name": name,
            "source": source,
            "language": value(elem, "language", "lang", "type", "compiler"),
            "interpreter": value(elem, "interpreter", "runtime"),
            "build": value(elem, "build", "build-command"),
            "output": value(elem, "output", "out", "binary", "install-from"),
            "args": value(elem, "args", "compiler-args", "flags"),
            "sources": value(elem, "sources"),
            "frameworks": value(elem, "frameworks"),
            "chmod": value(elem, "chmod", "executable"),
        }
        if not command["source"] and not command["build"] and not command["output"]:
            fail(f"command '{name}' needs source, build, or output")
        commands.append(command)
    if not commands:
        fail("no <command> entries found")
    names = [cmd["name"] for cmd in commands]
    duplicates = sorted({name for name in names if names.count(name) > 1})
    if duplicates:
        fail("duplicate command names: " + ", ".join(duplicates))
    return commands

try:
    root = ET.parse(info_path).getroot()
except ET.ParseError as exc:
    fail(f"invalid XML in info.xml: line {exc.position[0]}, column {exc.position[1]}: {exc.msg}")
except OSError as exc:
    fail(f"cannot read info.xml: {exc}")

requires = []
for elem in root.iter():
    if tag(elem) in {"require", "dependency", "tool"}:
        tool = value(elem, "name", "tool", "command") or (elem.text or "").strip()
        if tool:
            requires.append(tool)
for tool in requires:
    need(tool, f"info.xml requirement")

commands = parse_commands(root)
install_dir.mkdir(parents=True, exist_ok=True)
installed_names = []

for command in commands:
    name = command["name"]
    if command["build"]:
        run(command["build"])
        built = find_output(command)
    elif command["output"] and not command["source"]:
        built = find_output(command)
    else:
        built = compile_source(command)
    if not built.is_file():
        fail(f"command '{name}' did not create a file")
    target = install_dir / name
    shutil.copy2(built, target)
    target.chmod(target.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    installed_names.append(name)

manifest_dir.mkdir(parents=True, exist_ok=True)
manifest_name = module_key.replace("/", "__")
(manifest_dir / manifest_name).write_text(
    "module=" + module_key + "\n"
    "installed_at=" + __import__("datetime").datetime.now().strftime("%Y-%m-%d %H:%M:%S") + "\n"
    "install_dir=" + str(install_dir) + "\n"
    "commands=" + " ".join(shlex.quote(name) for name in installed_names) + "\n"
    "metadata=info.xml\n"
)
print("Installed: " + ", ".join(installed_names))
PY
  finish_progress "Done. Installed successfully."
}

install_legacy_repo_dir() {
  local repo_dir="$1"
  local module_key="${2:-local/${repo_dir:t}}"
  [ -d "$repo_dir/src" ] || die "repo must contain src/ or info.xml"
  [ -f "$repo_dir/make.sh" ] || die "repo must contain make.sh or info.xml"

  local build_dir="$repo_dir/.tlib-build"
  mkdir -p "$build_dir"

  run_step "Preparing" "Prepared" "Preparation failed" mkdir -p "$INSTALL_DIR" "$build_dir" || return 1
  (cd "$repo_dir" && run_step "Running make.sh" "make.sh complete" "make.sh failed" zsh ./make.sh) || return 1

  local installed=0
  local -a installed_names
  installed_names=()
  local source name built out
  for source in "$repo_dir"/src/*(.N); do
    [ -f "$source" ] || continue
    name="$(command_name_for_source "$source")"
    built="$(find_built_command "$repo_dir" "$name" || true)"
    if [ -z "$built" ]; then
      out="$build_dir/$name"
      run_step "Compiling $name" "Compiled $name" "Build failed" compile_one_source "$source" "$out" || return 1
      built="$out"
    fi
    run_step "Installing $name" "Installed $name" "Installation failed" install_command_file "$built" "$name" || return 1
    installed_names+=("$name")
    installed=$((installed + 1))
  done

  [ "$installed" -gt 0 ] || die "no source files found in src/"
  write_manifest "$module_key" "${installed_names[@]}"
  finish_progress "Done. Installed successfully."
}

install_repo_dir() {
  local repo_dir="$1"
  local module_key="${2:-local/${repo_dir:t}}"
  if [ -f "$repo_dir/info.xml" ]; then
    install_info_xml "$repo_dir" "$module_key"
  else
    install_legacy_repo_dir "$repo_dir" "$module_key"
  fi
}

install_spec() {
  local spec="$1"
  local parts owner repo branch repo_dir
  parts="$(repo_parts_from_spec "$spec")" || die "expected RepoName, Bluegrayfoo/RepoName, or a GitHub URL"
  owner="${parts[(w)1]}"
  repo="${parts[(w)2]}"
  branch="${parts[(w)3]}"
  repo_dir="$CACHE_DIR/repos/${owner}/${repo}/${branch}"

  run_step "Downloading $owner/$repo" "Downloaded $owner/$repo" "Download failed" download_repo "$owner" "$repo" "$branch" "$repo_dir" || exit 1
  install_repo_dir "$repo_dir" "$(module_key_from_parts "$owner" "$repo")"
}

uninstall_spec() {
  local spec="$1"
  local parts owner repo key manifest commands line command
  parts="$(repo_parts_from_spec "$spec")" || die "expected RepoName, Bluegrayfoo/RepoName, or a GitHub URL"
  owner="${parts[(w)1]}"
  repo="${parts[(w)2]}"
  key="$(module_key_from_parts "$owner" "$repo")"
  manifest="$(manifest_path_for_key "$key")"
  [ -f "$manifest" ] || die "$key is not installed by tlib"
  line="$(grep '^commands=' "$manifest" || true)"
  commands="${line#commands=}"
  [ -n "$commands" ] || die "install manifest for $key has no commands"

  run_step "Reading install record" "Found install record" "Uninstall failed" test -f "$manifest" || return 1
  for command in ${(z)commands}; do
    run_step "Removing $command" "Removed $command" "Uninstall failed" rm -f "$INSTALL_DIR/$command" || return 1
  done
  rm -f "$manifest"
  finish_progress "Done. Uninstalled $key."
}

doctor() {
  local ok=1
  print -- "TLib doctor"
  print -- "install dir: $INSTALL_DIR"
  print -- "cache dir: $CACHE_DIR"
  if [ -d "$INSTALL_DIR" ] && [ -w "$INSTALL_DIR" ]; then print -- "✓ ~/cmds is writable"; else print -- "✗ ~/cmds is not writable or does not exist"; ok=0; fi
  for tool in curl tar zsh python3; do
    if have "$tool"; then print -- "✓ $tool found"; else print -- "✗ $tool missing"; ok=0; fi
  done
  if have clang; then print -- "✓ clang found"; else print -- "! clang missing, C/Objective-C builds will fail"; fi
  if have clang++; then print -- "✓ clang++ found"; else print -- "! clang++ missing, C++ builds will fail"; fi
  if have swiftc; then print -- "✓ swiftc found"; else print -- "! swiftc missing, Swift builds will fail"; fi
  if have go; then print -- "✓ go found"; else print -- "! go missing, Go builds will fail"; fi
  if have rustc; then print -- "✓ rustc found"; else print -- "! rustc missing, Rust builds will fail"; fi
  [ "$ok" -eq 1 ] || return 1
}

main() {
  local cmd="${1:-}"
  case "$cmd" in
    install)
      [ "$#" -eq 2 ] || die "usage: tlib install RepoName"
      install_spec "$2"
      ;;
    install-owner)
      [ "$#" -eq 3 ] || die "usage: tlib install-owner Bluegrayfoo RepoName"
      install_spec "$2/$3"
      ;;
    local)
      [ "$#" -eq 2 ] || die "usage: tlib local /path/to/repo"
      run_step "Opening local module" "Opened local module" "Open failed" test -d "$2" || exit 1
      install_repo_dir "$2" "local/${2:t}"
      ;;
    uninstall)
      [ "$#" -eq 2 ] || die "usage: tlib uninstall RepoName"
      uninstall_spec "$2"
      ;;
    doctor)
      doctor
      ;;
    --version)
      print -- "TLib 2, TLibH 1"
      ;;
    help|-h|--help|"")
      usage
      ;;
    *)
      die "unknown command: $cmd"
      ;;
  esac
}

main "$@"
