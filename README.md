<p align="center">
  <img src="assets/fuzzy-manual.png" alt="A fuzzy, glowing book labeled MANUAL" width="320">
</p>

<h1 align="center">Read The <s>F@%$#!</s> Fuzzy Manual</h1>

<p align="center"><strong>RTFM</strong> — a zsh plugin that finds command options, arguments, and paths from the real manual, blazingly fast.</p>

<p align="center">
  <a href="#showcase">Showcase</a> ·
  <a href="#install">Install</a> ·
  <a href="#keys">Keys</a> ·
  <a href="#nitty-griddy">Nitty Griddy</a>
</p>

---

## Why

In an age of autocomplete, Stack Overflow snippets, and AI that will happily invent flags, it is still worth going back to the fundamentals: the **manual** that shipped with the tool.

RTFM puts that manual under your thumb. Hit **Tab**, fuzzy-filter what you need, read the description, insert the token — without leaving the line, and without guessing.

It is a **zsh** plugin powered by **fzf**. It reads **man** pages (and `--help` when man is missing), understands common subcommands, and browses files when the command wants a path.

**Enter never runs the command.** It only inserts text onto your line.

---

## Showcase

### Options from the man page

```text
$ ls <Tab>
```

A floating picker opens: left column is every option/argument from `ls(1)`, right column is the description. Type `color` or `human` to filter. **Enter** inserts the pick and returns you to the shell; **Tab** inserts and **keeps the picker open** so you can stack flags.

```text
$ ls --author --color[=WHEN] -l _
        ↑ already chosen tokens disappear from the next list
```

### Subcommands

```text
$ docker p<Tab>          → filter stays on "p" (incomplete)
$ docker ps<Tab>         → opens docker-ps options (--all, -q, …)
$ git sta<Tab>           → incomplete prefix stays as the query
$ git status<Tab>        → git-status man options
```

### Paths when they matter

```text
$ cat <Tab>              → options + files/dirs in the cwd (and /)
$ cat /<Tab>             → directories under / only (no man noise)
$ cd src/<Tab>           → directories under src/ only
$ mv <Tab>               → pick src, Tab again for dst (stays open)
```

Zoom into a directory with **Tab**: the list shows **child names only** (`file`, `nested`), not `src/file`. Insert still uses the full path.

### Regex hunt inside options

```text
$ ls <Tab>
  Ctrl-f
  regex> author|help
  Enter                  → filtered list of matches
  n / N                  → jump between matches
```

### Wrappers and special tools

```text
$ sudo docker ps <Tab>   → skips sudo; shows docker-ps options
$ ip addr <Tab>          → ip-address man options / verbs
$ sv status <Tab>        → services under $SVDIR
```

### In-picker help

Press **?** inside any picker for a short key guide (**q** to close).

---

## What you get

| Area | Behavior |
|------|----------|
| **Commands** | Tab on the first word → PATH executables + selected builtins; one match chains into options in the same Tab |
| **Options / args** | From **man** when possible, else `--help` / `-h`; sub-man pages like `git-status` |
| **Paths** | Mixed in when usage looks like it takes a file; depth-1 browse; zoom with Tab |
| **Already used** | Options and path tokens already on the line are dropped from the next picker |
| **Preview** | Man/help text for options; `ls -ld` + contents for files; directory listing for dirs |
| **Safety** | Enter only inserts; Esc aborts; never executes the line |

---

## Install

### Requirements

- **zsh** (interactive, with ZLE)
- **fzf**
- **rg** (ripgrep)
- **man** and **col**
- Optional: **less** / **more**, **fzf-tmux**, **timeout**

### Plain `source`

```zsh
# ~/.zshrc — use your real clone path
source ~/src/RTFM/rtfm.plugin.zsh

# If fzf --zsh or compinit rebinds Tab, put this last:
fzf_rtfm_rebind_tab
```

### Oh My Zsh

```bash
git clone https://github.com/hoolies/RTFM.git \
  ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/rtfm
```

Add `rtfm` to `plugins=(…)` in `~/.zshrc`.

### Zinit

```zsh
zinit ice wait lucid
zinit snippet /FULL/PATH/TO/RTFM/fzf-man-opts.zsh
```

---

## Keys

### At the prompt

| Key | Action |
|-----|--------|
| **Tab** | Complete command, then options / arguments / paths |

### Inside the picker

| Key | Action |
|-----|--------|
| **Type** | Fuzzy-filter the token column |
| **↑ ↓** / **Ctrl-j** / **Ctrl-k** | Move |
| **← →** / **Ctrl-h** / **Ctrl-l** | Scroll preview |
| **Tab** | Zoom into a non-empty directory, or insert file/option/empty-dir and stay open |
| **Enter** | Insert and return to the shell (or apply a Ctrl-f filter while composing) |
| **Esc** | Abort, or cancel / clear Ctrl-f |
| **Alt-.** | Toggle hidden names (dotfiles) |
| **Ctrl-f** | Case-sensitive regex over options (then **n** / **N**\|**p**) |
| **?** | Help (**q** to close) |

---

## Environment

| Variable | Meaning |
|----------|---------|
| `FZF_RTFM_USE_TMUX` | Non-zero in tmux → use `fzf-tmux` (helps when typing fails in the pane) |
| `FZF_RTFM_TMUX_OPTS` | Extra `fzf-tmux` args; default `-d 90%` |
| `FZF_RTFM_HIST_DEPTH` | History lines for command-picker ranking (default `4000`) |
| `FZF_RTFM_NO_PATH_SCHEME` | `1` → skip `--scheme path` (very old fzf) |
| `SVDIR` | Runit services for `sv` (default `/service`, else `/var/service`) |

---

## Credits

Sources, tools, and inspiration: **[ATTRIBUTIONS.md](ATTRIBUTIONS.md)**.  
License: **[MIT](LICENSE)**.

---

## Nitty Griddy

Technical reference for contributors and anyone debugging the widget.

### Repository layout

| Path | Role |
|------|------|
| `fzf-man-opts.zsh` | Full implementation |
| `rtfm.plugin.zsh` / `rtfm` | Loaders |
| `tests/rtfm-unit.zsh` | Non-interactive unit tests |
| `assets/fuzzy-manual.png` | Logo |
| `ATTRIBUTIONS.md` | Credits |
| `LICENSE` | MIT |

### Feature details

**Command completion**

- Empty line or incomplete first word → PATH + builtins.
- One prefix match → insert `name ` and open the options picker in the same Tab.
- Several matches → fzf ranked by history frequency, then name.
- Path-shaped first token (`./`, `../`, `/…`, `~/…`) → directory listing, not PATH.

**Options and arguments**

- Prefer man (including `cmd-sub` topics); fall back to `--help` / `-h`.
- Token starting with `-` → options only (no file mix-in).
- Files mixed in when SYNOPSIS/usage suggests `FILE` / `PATH` / `<file>` / …
- Cwd listings include a top-level `/` entry.

**Path browsing**

- Always depth 1.
- After Tab-zoom, display **basenames**; insert/preview use the full path.
- Typed directory prefix → directories only, no man rows.
- `/` skips `/proc`, `/sys`, `/dev`, `/run`.
- No `..` entries. Hidden names on by default (**Alt-.** toggles).

**Special parsers**

| Command | Behavior |
|---------|----------|
| `ip` | Objects from `ip(8)`; then `ip-<object>` man pages |
| `docker` | `docker --help` / `docker SUB --help` |
| `sv` | OPTIONS + verbs; after a verb, services from `$SVDIR` |
| `cd` / `pushd` | zsh `-L`/`-P` only (no Tcl man cd); then dirs |

**Wrappers skipped:** `sudo` `doas` `command` `builtin` `env` `time` `nice` `nohup`

**UI:** centered fzf (~90% height), rounded border; ~20% token column, ~80% preview.

### Diagnostics

```zsh
fzf_diagnose_cmd git     # man/help/parse dump for one command
fzf_rtfm_diagnose        # TTY / fzf / environment dump
```

If Tab is still stock completion, call `fzf_rtfm_rebind_tab` at the **end** of `~/.zshrc`.  
If typing fails inside tmux: `export FZF_RTFM_USE_TMUX=1`.

**xtrace / `functions -t`:** Tab-continue rebuilds under `__fzf_rtfm_untrace` with stderr redirected (fixed fd 8) so locals and mktemp paths are not painted above the picker. Man pages are parsed from temp files, not kept as huge scalars. Re-source after a debug session if needed.

### Function reference

Functions are private (`__fzf_*`) except public helpers and widget entrypoints. Nested `*_fin` helpers exist for `trap` cleanup.

**Load-time / UI**

- `__fzf_rtfm_merged_path_scheme` — `--scheme path` when supported  
- `__fzf_rtfm_fzf_window_common`, `_fzf_binds_*`, `_fzf_preview_window` — shared geometry and keys  
- `__fzf_rtfm_print_help` / `_ensure_help_script` — **?** pager  
- `__fzf_rtfm_ensure_preview_script` / `_write_lister` / `_write_transformer` / `_write_toggler` — preview + in-fzf scripts (lister embeds `__fzf_rtfm_list_paths` / `_emit_file_row`)  
- `__fzf_rtfm_resolve_path_pick` — join picks onto a typed directory prefix  
- `__fzf_rtfm_man_options_from_topic` — OPTIONS-section-first man parse  
- `__fzf_rtfm_untrace` — clear `xtrace` / `functions -t` on RTFM helpers (name auto-discovery)  
- `__fzf_rtfm_tab_continue_rebuild` — Tab-continue state into a temp dir  

**TTY**

- `__fzf_tty_unfreeze` / `_refreeze`, `_drain_tty_input`  
- `__fzf_rtfm_stty_for_fzf` / `_restore`, `_zle_parent_tty_prepare` / `_restore`  
- `__fzf_rtfm_fzf_exec` — `fzf` or `fzf-tmux`  

**Docs ingest / parse**

- `__fzf_resolve_binary`, `__fzf_man_topic_exists`, `__fzf_get_help_text`  
- `__fzf_parse_dash_options_block`, `__fzf_parse_man_subcommands`  
- `__fzf_rtfm_text_wants_files`, `__fzf_rtfm_docs_text` / `_docs_trim`  
- Docker / ip / sv: `__fzf_docker_*`, `__fzf_ip_*`, `__fzf_sv_*`  
- `__fzf_build_entries` / `_cached` — router + cache  

**Tab / path / picker**

- `__fzf_zle_token_state`, `__fzf_rtfm_wsplit`  
- `__fzf_apply_pick` / `_dir_pick` / `_mixed_pick`  
- `__fzf_rtfm_path_only`, `_is_dir_prefix`, `_dir_has_entries`  
- `__fzf_rtfm_list_paths`, `_emit_file_row`, `_row_apply_token`, `_zoom_prompt`  
- `__fzf_tab_immediate_file_rows`, `__fzf_pick_mixed`, `__fzf_rtfm_browse_apply`  
- `__fzf_tab_try_command` / `_try_rtfm` / `_try_path_firstword`  
- `fzf_tab_unified_impl`, `fzf_rtfm_rebind_tab`  
- Public: `fzf_diagnose_cmd`, `fzf_rtfm_diagnose`  

At load: `zle -N` + `bindkey '^I'`.

### Tests

```bash
zsh -n fzf-man-opts.zsh
zsh tests/rtfm-unit.zsh
```

### Publishing (maintainers)

```bash
gh repo create RTFM --public --source=. --remote=origin \
  --description "Read The Fuzzy Manual — zsh Tab + fzf for man, help, and paths" --push
```
