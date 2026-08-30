# RTFM (Read The Fuzzy Manual)

A **zsh** plugin that binds **Tab (`^I`)** to a fuzzy **fzf** picker for:

1. Completing the **command** (PATH + shell builtins)
2. Completing **options / arguments** from man pages or `--help`
3. Browsing **files and directories** when that makes sense

Enter never runs the command — it only inserts text onto the line.

Details on sources and tools: **[ATTRIBUTIONS.md](ATTRIBUTIONS.md)**.

---

## Features

### Command completion (first word)

- Tab with no trailing space completes **PATH executables** and selected **shell builtins**.
- **One** prefix match → insert `name ` and open the options/arguments picker in the **same** Tab.
- **Several** matches → fzf command list (history frequency, then alphabetical).
- Empty line → full command list.
- Path-shaped first token (`./`, `../`, `/…`, `~/…`) → list that directory (not PATH).

### Options and arguments (after a space)

- Tab after `cmd ` opens fzf with **man / `--help` / `-h`** tokens when available.
- Subcommand man pages are used when present (e.g. `git-status`, `git-commit`).
- A token starting with `-` shows **options only** (no file list).
- Files/dirs are mixed in when usage/SYNOPSIS looks like it takes a path (`FILE`, `PATH`, `<file>`, …).
- Cwd listings include a top-level **`/`** entry.
- Fuzzy filter applies to the **token** column (left); the description is preview-only.

### Path browsing

- Listings are always **depth 1** (one level at a time).
- Typed directory (`src/`, `/`, existing dir) → **directories only**, **no** man options/arguments.
- **`/`** listing skips `/proc`, `/sys`, `/dev`, `/run`.
- Parent **`..`** entries are never listed.
- Hidden names (dotfiles) are shown by default; toggle with **Alt-.** (fzf cannot bind Ctrl-.).

### Tab vs Enter inside the picker

| Key | Behavior |
|-----|----------|
| **Tab** on a **non-empty directory** | Zoom into that directory (depth 1 children; files+dirs for path commands; dirs only for `cd`/`pushd`) |
| **Tab** on a **file, option, or empty directory** | Insert it (trailing space) and **keep the picker open** for the next token |
| **Enter** | Insert the current pick and **return to the shell** (does not run the command) |
| **Esc** | Abort; leave the command line unchanged |

Empty directory + Tab is useful for multi-arg paths, e.g. `mv /src /dst`.

### Ctrl-f regex search (options view only)

Available when man options/arguments are shown (not in path-only browse).

1. **Ctrl-f** — prompt becomes `regex> ` (typed text is visible; fuzzy filtering pauses)
2. Type a **case-sensitive regex** over option tokens and descriptions
3. **Enter** — **filter** the list to all matches (does not insert)
4. Browse with **arrows** or **n** (next) / **N** or **p** (previous)
5. **Tab** / **Enter** — insert as usual; **Esc** — cancel typing or clear the filter

### In-picker help

- **?** — open a pager with keybindings and how to use the plugin (**q** to close)

### Wrappers

These prefixes are skipped so Tab sees the real command:

`sudo` · `doas` · `command` · `builtin` · `env` · `time` · `nice` · `nohup`

### `cd` / `pushd`

- Does **not** use Tcl `man cd` or `man -k ^cd-` noise.
- Offers zsh **`-L`** / **`-P`**, then **directories only**.
- Path token → directories only (no option rows).

### Special command parsers

| Command | Behavior |
|---------|----------|
| **`ip`** | OBJECT list from `ip(8)` + global OPTIONS; after an object, verbs/options from `ip-<object>` man pages |
| **`docker`** | `docker --help` commands/options; after a subcommand, `docker SUB --help` |
| **`sv`** (runit) | OPTIONS + verbs; after a verb, service names from `$SVDIR` (default `/service`, else `/var/service`) |

### Preview pane

- **Options / arguments:** man or help description
- **Files:** `ls -ld` plus contents (text via `head`; binary summarized with `file`)
- **Directories:** `ls -ld` plus a short `ls -la` of children
- Scroll preview with **Left/Right** or **Ctrl-h** / **Ctrl-l**

### UI

- Centered floating fzf window (rounded border, margin/padding)
- Left ~20%: token · Right ~80%: preview

---

## Requirements

- **zsh** (interactive; ZLE required)
- **fzf** on `PATH`
- **rg** (ripgrep) — small filters (`usage:` detection, feature probes)
- **man** + **col** — manpage text
- Optional: **less** or **more** (help popup), **fd**, **fzf-tmux**, **timeout**, GNU/BSD **find**

---

## Install

### Plain source

```zsh
# In ~/.zshrc (use your real clone path)
source ~/path/to/RTFM/fzf-man-opts.zsh
# or:
source ~/path/to/RTFM/rtfm.plugin.zsh
```

### Oh My Zsh

```bash
git clone https://github.com/hoolies/RTFM.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/rtfm
```

Add `rtfm` to `plugins=(… rtfm …)` in `~/.zshrc`.

### Zinit

```zsh
zinit ice wait lucid
zinit snippet /FULL/PATH/TO/RTFM/fzf-man-opts.zsh
```

### After `compinit`

If stock completion **rebinds Tab** after this file loads, add **at the very end** of `~/.zshrc`:

```zsh
fzf_rtfm_rebind_tab
```

---

## Keys

### At the shell (ZLE)

| Key | Action |
|-----|--------|
| **Tab (`^I`)** | Command complete → options/args/paths picker (see Features) |
| **Alt-m** | Not bound |

### Inside fzf

| Key | Action |
|-----|--------|
| Arrows / **Ctrl-j** / **Ctrl-k** | Move selection |
| **Left/Right** or **Ctrl-h** / **Ctrl-l** | Scroll preview |
| Type | Fuzzy-filter the token column |
| **Tab** | Zoom into non-empty dir, or insert file/option/empty-dir and stay open |
| **Enter** | Insert pick and return to the shell (or run Ctrl-f filter while composing a regex) |
| **Esc** | Abort, or cancel Ctrl-f compose / clear filter |
| **Alt-.** | Toggle hidden names (dotfiles) |
| **Ctrl-f** | Regex search over options/arguments (case-sensitive); see Features |
| **n** / **N** \| **p** | Next / previous match after a Ctrl-f filter |
| **?** | Help popup (press **q** to close) |

---

## Environment variables

| Variable | Meaning |
|----------|---------|
| `FZF_RTFM_USE_TMUX` | Non-zero + valid `TMUX_PANE` → use `fzf-tmux` (helps some tmux setups where typing fails) |
| `FZF_RTFM_TMUX_OPTS` | Extra args for `fzf-tmux` (zsh word-split via `${=…}`); default `-d 90%` |
| `FZF_RTFM_HIST_DEPTH` | Max `fc` lines for history-based ranking (default `4000`) |
| `FZF_RTFM_NO_PATH_SCHEME` | Set to `1` to omit `--scheme path` for very old fzf |
| `SVDIR` | Runit service directory for `sv` (default `/service`, fallback `/var/service`) |

You can override **`typeset -ga __fzf_rtfm_fzf_window_common`** and the shared bind arrays **after** sourcing to tweak all pickers at once.

---

## Quick examples

```text
ls<Tab>                 → insert "ls ", open options + files
ls <Tab>                → same picker after a space
git sta<Tab>            → command/subcommand flow via man pages
cat /<Tab>              → directories under / only (no man options)
cd src/<Tab>            → directories under src/ only
mv <Tab> …              → Tab inserts paths and stays open for /dst
ls <Tab> then Ctrl-f    → regex> author|help  → Enter → filtered matches
?                       → help while any picker is open
```

---

## Diagnostics

```zsh
fzf_diagnose_cmd git    # how man/help looks for a command
fzf_rtfm_diagnose        # paste output when debugging terminal/fzf/tty issues
```

If Tab still runs only stock completion, call `fzf_rtfm_rebind_tab` at the end of `~/.zshrc`.  
If typing in fzf fails inside tmux: `export FZF_RTFM_USE_TMUX=1`.

---

## Repository layout

| File | Role |
|------|------|
| `fzf-man-opts.zsh` | Full implementation |
| `rtfm` | One-line `source` of the implementation |
| `rtfm.plugin.zsh` | Oh My Zsh-style loader |
| `ATTRIBUTIONS.md` | Credits, dependencies, inspiration |
| `LICENSE` | MIT |

---

## Publishing to GitHub

Replace `YOURUSER` and run once:

```bash
cd /path/to/RTFM
git init
git add .
git commit -m "Initial commit: RTFM (Read The Fuzzy Manual)"
gh repo create RTFM --public --source=. --remote=origin --description "Read The Fuzzy Manual — zsh fzf Tab for man, help, paths, and commands" --push
```

Without GitHub CLI: create an empty repo named **RTFM** in the web UI, then:

```bash
git remote add origin git@github.com:YOURUSER/RTFM.git
git branch -M main
git push -u origin main
```

---

## Function reference (nitty-gritty)

Functions are **private** (`__fzf_*`) except the public helpers and widget entrypoints. **Nested** functions (e.g. `__fzf_pick__fin`) exist only to pair with `trap` cleanup.

### Load-time configuration

- **`__fzf_rtfm_merged_path_scheme`** — Global array: empty or `( --scheme path )` if fzf supports it.
- **`__fzf_rtfm_fzf_window_common`** — Shared fzf geometry.
- **`__fzf_rtfm_fzf_binds_preview` / `_preview_nav` / `_basic`** — Shared keymaps (include **`?`** help bind after load).
- **`__fzf_rtfm_fzf_preview_window`** — `--preview-window` string (`right,80%,wrap`).
- **`__fzf_rtfm_print_help` / `__fzf_rtfm_ensure_help_script`** — Help text and pager script for **`?`**.

### TTY / terminal hygiene

- **`__fzf_tty_unfreeze` / `__fzf_tty_refreeze`** — `ttyctl -u` / `-f`.
- **`__fzf_rtfm_drain_tty_input`** — Drop pending keystrokes before the next fzf (avoids instant accept after Tab).
- **`__fzf_rtfm_stty_for_fzf` / `__fzf_rtfm_stty_restore`** — Cooked TTY inside `$(…)` fzf subshells.
- **`__fzf_rtfm_zle_parent_tty_prepare` / `_restore`** — Same on the parent shell during ZLE.
- **`__fzf_rtfm_normalize_query`** — Collapse whitespace on the query string.
- **`__fzf_rtfm_fzf_exec`** — `fzf` or `fzf-tmux` depending on env.

### Resolution / docs ingest

- **`__fzf_resolve_binary`** — `command -v` check.
- **`__fzf_man_topic_exists`** — `man -w` probe.
- **`__fzf_get_help_text`** — `binary --help` / `-h` (with `usage:`-ish detection).
- **`__fzf_compact_ws`** — Normalize description whitespace.
- **`__fzf_rtfm_text_wants_files`** — Detect whether usage suggests path args.

### Parsing (generic)

- **`__fzf_parse_dash_options_block`** — man/help → `token<TAB>description`.
- **`__fzf_parse_man_subcommands`** — `man -k "^$cmd-"` → subcommand names.

### Docker / `ip` / `sv`

- **Docker:** `__fzf_docker_root_entries`, `__fzf_docker_sub_options`
- **ip:** `__fzf_ip_root_entries`, `__fzf_ip_submanual_entries`, plus synopsis/OPTIONS helpers
- **sv:** `__fzf_sv_entries`, `__fzf_sv_should_offer_services`, `__fzf_sv_service_entries` (`$SVDIR`)

### Entry builder

- **`__fzf_build_entries`** — Router for `ip` / `sv` / `docker` / generic man+help. Optional full line for `sv` services.

### Diagnostics (public)

- **`fzf_diagnose_cmd`** / **`__fzf_diagnose_cmd`** — Man/help/parse dump for a command.
- **`fzf_rtfm_diagnose`** — Environment / TTY / fzf dump.

### Tab / path / picker layer

- **`__fzf_zle_token_state`** — Globals `prefix_rest`, `lastw`, `nwords` from `LBUFFER`.
- **`__fzf_apply_pick` / `__fzf_apply_dir_pick` / `__fzf_apply_mixed_pick`** — Insert tokens onto the line.
- **`__fzf_rtfm_path_only` / `__fzf_rtfm_is_dir_prefix` / `__fzf_rtfm_dir_has_entries`** — Path-token gating.
- **`__fzf_tab_immediate_file_rows`** — Depth-1 file/dir rows (hidden flag, `/` special case).
- **`__fzf_pick_mixed`** — Mixed man+path fzf (Tab/Enter expect, Alt-., Ctrl-f filter, `?` help).
- **`__fzf_rtfm_browse_apply`** — ZLE loop: Tab stays open after insert; Enter returns to the shell; dir zoom.
- **`__fzf_tab_try_command` / `__fzf_tab_try_rtfm` / `__fzf_tab_try_path_firstword`** — Tab phases.
- **`fzf_tab_unified_impl`** — Widget: command → options/args (auto-chain); no stock-completion fallback.
- **`fzf_rtfm_rebind_tab`** — Rebind `^I` after `compinit` / `fzf --zsh`.

At file bottom, **`zle -N`** registers the Tab widget and **`bindkey '^I'`**.

---

## Contributing

Issues and PRs welcome. Please run **`zsh -n fzf-man-opts.zsh`** before submitting changes.
