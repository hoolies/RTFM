# RTFM (Read The Fuzzy Manual)

A **zsh** plugin that binds **one intelligent Tab (`^I`)** and **Alt-m (`^[m`)** to a single ZLE widget. It gives you **fuzzy access to manual pages and `--help` output** without installing a second Tab-completion plugin that fights for the same key.

You wanted **seamless manual/help access**; you also wanted **path-aware Tab** (files, `cd`, `source`, command names) in the same place so two plugins would not compete for Tab. RTFM implements that as a **priority-ordered dispatcher**: try source/dot arguments, then `cd`/`pushd`, then generic paths, then first-token command picking, then “RTFM” option/subcommand picking, and only if nothing matches does it fall through to stock `expand-or-complete`.

---

## What it does (short)

It provides autocomplete suggestions from a fuzzy list that reads the manual, help file and history.

Special cases: **`ip`**, **`docker`**, **`sv`** (runit) have tailored parsers so lists match those CLIs. **`sv`** can list **services** under `$SVDIR` once a verb is on the line.

Details on sources and tools: **[ATTRIBUTIONS.md](ATTRIBUTIONS.md)**.

---

## Requirements

- **zsh** (interactive; ZLE required)
- **fzf** on `PATH`
- **rg** (ripgrep) — used for small filters (`usage:` detection, feature probes)
- **man** + **col** — manpage text
- Optional: **fd**, **fzf-tmux**, **timeout**, **GNU/BSD find**

---

## Install

### Plain source

```zsh
# In ~/.zshrc (use your real clone path)
source ~/path/to/RTFM/fzf-man-opts.zsh
```

### Oh My Zsh

Clone into custom plugins:

```bash
git clone https://github.com/YOU/RTFM.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/fzf-man-opts.zsh
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

## Keys and `fzf` UI

- **Tab (`^I`)** — unified widget (`fzf_tab_unified_widget` → `fzf_tab_unified_impl`)
- **Alt-m (`^[m`)** — same implementation (`fzf_man_opts_widget`)

Inside **fzf**:

- Move: arrows, **Ctrl-j** / **Ctrl-k**
- Scroll preview: **Left/Right** or **Ctrl-h** / **Ctrl-l**
- Accept: **Tab** or **Enter**
- Abort: **Esc**

Preview column shows descriptions; fuzzy search targets the **token** column (where applicable).

---

## Environment variables

| Variable | Meaning |
|----------|---------|
| `FZF_RTFM_USE_TMUX` | Non-zero + valid `TMUX_PANE` → use `fzf-tmux` (helps some tmux setups) |
| `FZF_RTFM_TMUX_OPTS` | Extra args for `fzf-tmux` (zsh word-split via `${=…}`) |
| `FZF_RTFM_HIST_DEPTH` | Max `fc` lines for **source/cd** merged history and **command** history stats (default `4000`) |
| `FZF_RTFM_NO_PATH_SCHEME` | Set to `1` to omit `--scheme path` for old fzf |

You can override **`typeset -ga __fzf_rtfm_fzf_window_common`** and related arrays **after** sourcing to tweak all pickers at once (see script header).

---

## Diagnostics

```zsh
fzf_diagnose_cmd git    # how man/help looks for a command
fzf_rtfm_diagnose        # paste output when debugging terminal/fzf/tty issues
```

---

## Repository layout

| File | Role |
|------|------|
| `fzf-man-opts.zsh` | Full implementation (~1.7k lines) |
| `rtfm` | One-line `source` of the implementation (short path) |
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

Functions are **private** (`__fzf_*`) except the public helpers and widget entrypoints at the bottom. **Nested** functions (e.g. `__fzf_pick__fin`) exist only to pair with `trap` cleanup and are noted under their caller.

### Load-time configuration

- **`__fzf_rtfm_merged_path_scheme`** — Global array: either empty or `( --scheme path )` if fzf supports it (probe via `fzf --help | rg`).
- **`__fzf_rtfm_fzf_window_common`** — Shared `fzf` geometry: height, min-height, layout, border, margin, padding.
- **`__fzf_rtfm_fzf_binds_preview` / `__fzf_rtfm_fzf_binds_basic`** — Shared keymaps (with or without preview scroll binds).
- **`__fzf_rtfm_fzf_preview_window`** — String for `--preview-window` (`right,80%,wrap`).

### TTY / terminal hygiene

- **`__fzf_is_empty`** — True if `$1` is empty (string test helper).
- **`__fzf_tty_unfreeze` / `__fzf_tty_refreeze`** — Wrap `ttyctl -u` / `-f` so `fzf` can switch line discipline under zsh’s default frozen TTY.
- **`__fzf_rtfm_stty_for_fzf` / `__fzf_rtfm_stty_restore`** — Inside **`$(…)`** subshells running `fzf`: save `stty -g`, force sane/cooked mode, restore after `fzf` exits.
- **`__fzf_rtfm_zle_parent_tty_prepare` / `_restore`** — Same idea on the **parent** shell while a ZLE widget runs (ZLE often leaves the real TTY non-canonical).
- **`__fzf_rtfm_normalize_query`** — Collapses whitespace on the fzf query string (`awk`).
- **`__fzf_rtfm_fzf_exec`** — Runs **`fzf`** or **`fzf-tmux`** depending on env (`FZF_RTFM_USE_TMUX`, `TMUX_PANE`).

### Resolution / docs ingest

- **`__fzf_resolve_binary`** — `command -v` check; prints resolved path or errors to stderr.
- **`__fzf_man_topic_exists`** — `man -w` probe.
- **`__fzf_get_help_text`** — Runs `binary --help` / `-h` (and `sv` stderr hack); requires a `usage:`-ish line (`rg`); returns text or status `2`.
- **`__fzf_compact_ws`** — Normalizes whitespace in a description string.

### Parsing (generic)

- **`__fzf_parse_dash_options_block`** — Reads stdin or `$1`; **awk** state machine that turns man/help-like text into **`token<TAB>description`** (handles continuations, placeholder args `<foo>`).
- **`__fzf_parse_man_subcommands`** — `man -k "^$cmd-"` → short subcommand names + descriptions (`git`-style pages).

### Docker

- **`__fzf_docker_root_entries`** — Parses **`docker --help`**: command sections + global options.
- **`__fzf_docker_sub_options`** — Parses **`docker $sub --help`** option tables.

### `ip` (iproute2)

- **`__fzf_ip_man_colb`** — `man $topic | col -b`.
- **`__fzf_ip_synopsis_object_names`** — Pulls **`OBJECT := { … }`** from main `ip` manpage.
- **`__fzf_ip_canonical_object`** — Maps user token to best OBJECT name (exact / shortest prefix).
- **`__fzf_ip_resolve_man_topic`** — Maps OBJECT → **`ip-<object>`** page name with neighbor/neighbour etc. aliases.
- **`__fzf_ip_extract_options_section`** — **Awk** slice: from **`OPTIONS`** until known section headers (stops on SEE ALSO, `IP LINK`, …).
- **`__fzf_ip_object_blurbs_from_syntax`** — Optional descriptions from **`IP - COMMAND SYNTAX`** block.
- **`__fzf_ip_root_entries`** — Merges OBJECT list + blurbs + global OPTIONS parsed options.
- **`__fzf_ip_extract_synopsis_verbs`** — Verbs inside `{ a | b }` groups in SYNOPSIS (per-object pages).
- **`__fzf_ip_submanual_entries`** — For one OBJECT: verbs + OPTIONS from **`ip-<object>`**.

### `sv` (runit)

- **`__fzf_sv_runit_command_rows`** — Here-doc of standard **sv** verbs (static reference).
- **`__fzf_sv_usage_line`** — Extract usage line from `man sv` or first stderr line.
- **`__fzf_sv_entries`** — Merges OPTIONS from man + `sv --help` / `-h` + synthetic `-v`/`-w` hints + verb table.
- **`__fzf_sv_is_verb`** — Case match on runit verbs.
- **`__fzf_sv_should_offer_services`** — Zsh **`${(z)…}`** word splitting on full line: after options, sees verb → services mode.
- **`__fzf_sv_service_entries`** — Lists service names under `$SVDIR` or `/var/service`.

### Command line understanding (ZLE)

- **`__fzf_get_cmd_and_sub`** — From **`LBUFFER`**: strips optional **`sudo`**, **`builtin`/`command` chains**; outputs **`cmd<TAB>sub`** where `sub` is first non-option word after `cmd`.

### Entry builder (dispatches by `cmd`)

- **`__fzf_build_entries`** — Central router: **`ip`**, **`sv`**, **`docker`**, else generic **man / help** pipeline. Optional **`$3`** full line for **`sv`** service detection. Returns lines on stdout; **`2`** means “no docs” for widget to swallow quietly.

### Diagnostics (user-facing)

- **`__fzf_diagnose_cmd`** — Prints man, `man -k`, help samples, parse counts for a named binary.
- **`fzf_diagnose_cmd`** — Public thin wrapper.
- **`fzf_rtfm_diagnose`** — Environment dump: zsh/fzf/tty/`FZF_DEFAULT_OPTS` warnings.

### RTFM picker (options / subcommands)

- **`__fzf_pick`** — Spawns **fzf** with shared window + preview of second column; **trap** + **`__fzf_pick__fin`** restore parent TTY and ttyctl.

### Tab / path / history widget layer

- **`__fzf_zle_token_state`** — Sets globals **`prefix_rest`**, **`lastw`**, **`nwords`** from **`LBUFFER`** (handles trailing space = new empty token).
- **`__fzf_apply_pick`** — Replaces last token: **`prefix_rest picked␠`**.
- **`__fzf_tab_finish_fzf_pick`** — Normalizes fzf/rc: **`2`** → redisplay only; failure → return; else calls apply hook with picked string.
- **`__fzf_tab_path_token_dir_base`** — Derives **`dir`** + **`base`** from **`lastw`** / optional path fragment; expands leading `~`.
- **`__fzf_tab_apply_merged_hist_path_pick`** — Decodes **`h<TAB>…`** vs **`p<TAB>…`** rows from merged list.
- **`__fzf_last_word_is_pathlike`** — Heuristic: `/*`, `./`, `../`, `~*`, `*/*`.
- **`__fzf_expect_path_arg`** — Previous word is a “path verb” (`cp`, `mv`, …) but not `cd`/`pushd`.
- **`__fzf_tab_is_command_position`** — Empty line or sole **`sudo`** prefix.
- **`__fzf_tab_first_cmd_word_after_modifiers`** — Walks **`builtin`/`command`**; sets **`REPLY`** to real command word.
- **`__fzf_tab_is_source_or_dot_arg` / `_cd_or_pushd_arg`** — Predicate wrappers on **`REPLY`**.

### History

- **`__fzf_hist_shell_verb_lines`** — **`fc`** back-end, **`awk`** filter for `source`/. or cd/pushd (+ sudo/builtin forms), dedupe.
- **`__fzf_hist_source_dot_lines` / `_cd_pushd_lines`** — Mode wrappers.
- **`__fzf_apply_source_hist_pick`** — Rebuilds line with picked **history line** as new argument.

### Candidate files + merged fzf

- **`__fzf_tab_build_source_arg_candidate_file`** — Writes **`h`/`p`** TSV file: history + filesystem files.
- **`__fzf_tab_build_cd_arg_candidate_file`** — Same with dirs only + optional **`/`** toplevel when **`dir==.`**; awk dedupe.
- **`__fzf_tab_pick_hist_path_merged`** — Builds temp **sh** preview helper; **trap** + **`__fzf_hpmerged_fin`** removes it and restores TTY; runs **fzf** with **`--nth=1,2`** and path scheme.
- **`__fzf_tab_pick_source_arg`** — Calls merged picker with **`src+path>`** prompt.
- **`__fzf_tab_try_source_arg` / `_try_cd_arg`** — Orchestrate temp files, merged pick, **`__fzf_tab_finish_fzf_pick`**.

### Command picker

- **`__fzf_path_executable_names`** — Iterates **`commands`** hash; prints executable basenames with real paths.
- **`__fzf_rtfm_cmd_picker_shell_words`** — Builtin-ish words that are not PATH files but valid first tokens.
- **`__fzf_hist_first_word_counts`** — **`fc`** → **awk** counts → sort by frequency; feeds scores.
- **`__fzf_tab_pick_command`** — Merges scores + candidate names; **fzf** with numeric sort; **trap** + **`__fzf_pick_cmd_fin`**.
- **`__fzf_tab_try_command`** — Runs hist file + picker + apply.

### Plain path picker

- **`__fzf_tab_pick_path`** — **`fd`/`find`** piped to **fzf** with file preview; **trap** + **`__fzf_tab_path_fin`**.
- **`__fzf_tab_try_path`** — Gate on pathlike / path-verb context; not **`cd`/`pushd`** branch.

### RTFM from tab dispatcher

- **`__fzf_tab_try_rtfm`** — Parses cmd/sub, **`__fzf_build_entries`**, **`__fzf_pick`**, applies token.

### Widget entrypoints

- **`fzf_tab_unified_impl`** — Runs try-chain: **source → cd → path → command → rtfm** → else **`zle .expand-or-complete`**.
- **`fzf_man_opts_widget`** — Alias to unified impl.
- **`fzf_rtfm_rebind_tab`** — **`bindkey '^I' fzf_tab_unified_widget`** helper after **`compinit`**.

At file bottom, **`zle -N`** registers widgets and default **`bindkey`** for **`^I`** and **`^m`**.

---

## Contributing

Issues and PRs welcome. Please run **`zsh -n fzf-man-opts.zsh`** before submitting changes.
