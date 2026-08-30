#!/usr/bin/env zsh
# vim: set filetype=zsh :
# shellcheck shell=bash
# Bash-dialect scan only (no zsh mode). For a full advisory list, comment out the following disable= line, then run this file through the shellcheck(1) tool at severity=style in bash mode.
# shellcheck disable=SC2296,SC2206,SC2016,SC2153,SC2119,SC2154,SC2015
#
# fzf-man-opts.zsh
#
# HOW TO LOAD (zsh-only; this file defines ZLE widgets — it must be read into an *interactive* zsh)
#
#   source /FULL/PATH/TO/fzf-man-opts.zsh
#   # same in zsh:
#   . /FULL/PATH/TO/fzf-man-opts.zsh
#
# If you ARE in zsh and manual `source` works, but a *plugin, task runner, or IDE* says `source` is "not found":
#   • `command source file` is WRONG — `command` forces an *external* program; there is no /usr/bin/source.
#     Use plain `source` / `.` or:  builtin source /path/to/fzf-man-opts.zsh
#   • Loading via `sh -c 'source …'` or a non-zsh interpreter will fail or mis-detect builtins.
#   • Linter/LSP (ShellCheck, bash-language-server) may flag `source` if they assume dash — that is static
#     analysis noise, not the real shell; set file type to zsh (see modeline above) or disable that rule.
#   • Zinit:  zinit ice wait lucid; zinit snippet /FULL/PATH/TO/fzf-man-opts.zsh
#
# If you see  "source: not found"  at the *terminal* (not an editor):
#   • Your current shell is almost certainly NOT zsh — often it is /bin/sh (dash), which has no `source`.
#   • Fix:  exec zsh  then  source …
#   • Never:  sudo source …  — use  sudo zsh -ic 'source /path/…'
#
# Check what you are running:  echo $SHELL   ps -p $$ -o comm=
# Use a real path (container / remote workspace paths may differ from ~/... on the host).
# Tab:
# - First word with no trailing space (or an empty line): $PATH executables + builtins.
#   Path-shaped first token (./, ../, /..., ~/): list that directory (not PATH).
#   Exact prefix match of one name inserts "name "; several matches: fzf (history then alphabetical).
#   After the command is inserted ("cmd "), the options/arguments picker opens in the same Tab.
# - After a space following the real command: man/--help tokens, then cwd files/dirs when usage
#   looks like it takes a path. Token starting with "-" is options only.
# - cd/pushd after a space: zsh -L/-P, then directories only (not Tcl man / man -k ^cd-). No .. entries.
# - Cwd with no directory prefix: one-level files/dirs (plus /) mixed with man options.
#   Typed directory (src/, /): paths only (no man options/args), directories only at depth 1.
#   Tab into a non-empty directory: show that directory's immediate children as
#   names only (not parent/child); insert still uses the full path. Depth 1 again;
#   files+dirs for path cmds; dirs only for cd/pushd. Empty dir: insert with trailing space.
#   / stays dirs-only. No .. entries. Alt-. toggles hidden names (fzf cannot bind Ctrl-.).
#   Tab on a file/option/empty-dir inserts it and keeps the picker open for the next token.
#   Enter inserts the current pick and returns to the shell prompt. Esc leaves the line unchanged.
# - Wrappers skipped: sudo doas command builtin env time nice nohup
# - Special parsers: ip, docker, sv (then files by the same usage rule)
# - No Alt-m bind. One picker per Tab (directory Tab stays inside that picker).
# - Uses man pages (and sub-man pages like git-status / git-commit) when available
# - Otherwise falls back to `binary --help` / `binary -h`
# - UI: left token, right description (man text, or size+permissions for files)
# - Special cases:
#   * ip(8): uses OBJECT list from ip(8) plus options from per-object man pages (ip-<object>)
#   * sv(8) (runit): OPTIONS + verbs first; after a verb, services under $SVDIR (/service, /var/service)
#   * docker: uses docker --help parsing and docker SUB --help parsing
# - UI:
#   * Centered floating fzf window with rounded border and margin
#   * Left column (20% area): option/subcommand token (fuzzy searched)
#   * Right column (80% preview): description text (preview only, not searched)
#   * Keymaps:
#       arrows / Ctrl-J / Ctrl-K to move
#       Left/Right or Ctrl-H/Ctrl-L to scroll preview up/down
#       Tab: enter a non-empty directory (depth 1); insert a file/option/empty-dir and stay open
#       Alt-.: toggle hidden names (dotfiles; fzf cannot bind Ctrl-.)
#       Ctrl-f: (options view only) type a case-sensitive regex in the input line (regex> );
#               Enter filters the list to all matching options/args; n / N|p move among them;
#               Esc cancels compose or clears the filter (restores the full list)
#       Enter: insert the current pick and return to the shell (does not run the command);
#              while composing a Ctrl-f regex, Enter runs the filter instead
#       Esc: abort (or cancel Ctrl-f regex compose / clear active search filter)
#       ?: show keybindings / usage help (pager; press q to close)
#
# Diagnostic (after source):  fzf_diagnose_cmd git   # or __fzf_diagnose_cmd sv
# If fzf opens but typing does not appear in the query:  fzf_rtfm_diagnose  (paste output when asking for help)
#
# If Tab still runs only stock completion, compinit may have rebound ^I after this file;
# add at the very end of .zshrc:  fzf_rtfm_rebind_tab
#
# In tmux, if typing in fzf still fails:  export FZF_RTFM_USE_TMUX=1  (uses fzf-tmux -d 90%)
#
# Optional env: FZF_RTFM_HIST_DEPTH (default 4000) caps fc lines for first-token command-picker history stats;
#               FZF_RTFM_NO_PATH_SCHEME=1 disables --scheme path for very old fzf.

# ---------- Basic helpers ----------
__fzf_is_empty() { [[ -z "$1" ]]; }

# zsh freezes the tty by default (ttyctl -f); fzf cannot switch line discipline until we unfreeze.
__fzf_tty_unfreeze() {
  builtin ttyctl -u 2>/dev/null || true
}
__fzf_tty_refreeze() {
  builtin ttyctl -f 2>/dev/null || true
}

# Drop pending keystrokes (e.g. Tab/Enter that closed a prior picker) so the next
# fzf does not immediately accept or abort.
__fzf_rtfm_drain_tty_input() {
  local _c
  while read -k 1 -t 0 _c 2>/dev/null; do
    :
  done
}

# Inside $(...) subshells: line editor often leaves the TTY non-canonical; fzf needs cooked mode for the query line.
__fzf_rtfm_stty_for_fzf() {
  # Not function-local: __fzf_rtfm_stty_restore must read this from the same subshell.
  __fzf_rtfm_saved_stty=$(command stty -g 2>/dev/null) || __fzf_rtfm_saved_stty=
  command stty sane 2>/dev/null || true
  command stty isig icanon echo 2>/dev/null || true
}

__fzf_rtfm_stty_restore() {
  [[ -n $__fzf_rtfm_saved_stty ]] && command stty "$__fzf_rtfm_saved_stty" 2>/dev/null || true
  __fzf_rtfm_saved_stty=
}

# Export FZF_RTFM_USE_TMUX=1 if typed input works nowhere except via fzf-tmux (common in some tmux setups).
# Trim and collapse whitespace so an extra space does not break matching.
__fzf_rtfm_normalize_query() {
  emulate -L zsh
  [[ -z "${1-}" ]] && return 0
  print -r -- "$1" | command awk '{gsub(/^[[:space:]]+|[[:space:]]+$/,""); gsub(/[[:space:]]+/," "); print}'
}

# Prefer POSIX sh for fzf child processes. With SHELL=zsh, preview/transform
# run via `zsh -c` and man text with quotes ('always', 'table') dumps as a
# parse error above the picker — especially on the second Tab.
typeset -ga __fzf_rtfm_with_shell
__fzf_rtfm_with_shell=()
if command fzf --help 2>/dev/null | command rg -q -- '--with-shell' 2>/dev/null; then
  if [[ -x /bin/sh ]]; then
    __fzf_rtfm_with_shell=(--with-shell='/bin/sh -c')
  elif command -v sh >/dev/null 2>&1; then
    __fzf_rtfm_with_shell=(--with-shell='sh -c')
  fi
fi

__fzf_rtfm_fzf_exec() {
  # Child preview/transform must not inherit SHELL=zsh (quote dumps) or a
  # user FZF preview that interpolates the full line.
  local -x SHELL=/bin/sh
  local -x FZF_DEFAULT_OPTS="${FZF_DEFAULT_OPTS-}"
  if [[ ${FZF_RTFM_USE_TMUX-0} != 0 ]] && [[ -n ${TMUX_PANE-} ]] && command -v fzf-tmux >/dev/null 2>&1; then
    if [[ -n ${FZF_RTFM_TMUX_OPTS-} ]]; then
      # zsh ${=var}: word-split into argv for fzf-tmux; quoted form would pass a single token
      # shellcheck disable=SC2086
      command fzf-tmux ${=FZF_RTFM_TMUX_OPTS} -- "${__fzf_rtfm_with_shell[@]}" "$@"
    else
      command fzf-tmux -d 90% -- "${__fzf_rtfm_with_shell[@]}" "$@"
    fi
  else
    command fzf "${__fzf_rtfm_with_shell[@]}" "$@"
  fi
}

# Optional extra args for src+path / cd+dir fzf (skip --scheme if fzf is too old; override with FZF_RTFM_NO_PATH_SCHEME=1).
typeset -ga __fzf_rtfm_merged_path_scheme
if [[ ${FZF_RTFM_NO_PATH_SCHEME-0} != 0 ]]; then
  __fzf_rtfm_merged_path_scheme=()
elif command fzf --help 2>/dev/null | command rg -q -- '--scheme' 2>/dev/null; then
  __fzf_rtfm_merged_path_scheme=(--scheme path)
else
  __fzf_rtfm_merged_path_scheme=()
fi

# Shared fzf UI fragments (geometry + keymaps) — keep Tab and RTFM pickers visually consistent.
typeset -ga __fzf_rtfm_fzf_window_common
__fzf_rtfm_fzf_window_common=(
  --height=90%
  --min-height=20
  --layout=reverse
  --border=rounded
  --margin=2%
  --padding=1
)
typeset -ga __fzf_rtfm_fzf_binds_preview
__fzf_rtfm_fzf_binds_preview=(
  --bind 'ctrl-j:down,ctrl-k:up'
  --bind 'left:preview-up,right:preview-down'
  --bind 'ctrl-h:preview-up,ctrl-l:preview-down'
  --bind 'tab:accept,enter:accept'
  --bind 'esc:abort'
)
# Path/man mixed picker: Tab/Enter are --expect keys (see __fzf_pick_mixed), not accept binds.
typeset -ga __fzf_rtfm_fzf_binds_preview_nav
__fzf_rtfm_fzf_binds_preview_nav=(
  --bind 'ctrl-j:down,ctrl-k:up'
  --bind 'left:preview-up,right:preview-down'
  --bind 'ctrl-h:preview-up,ctrl-l:preview-down'
  --bind 'esc:abort'
)
typeset -ga __fzf_rtfm_fzf_binds_basic
__fzf_rtfm_fzf_binds_basic=(
  --bind 'ctrl-j:down,ctrl-k:up'
  --bind 'tab:accept,enter:accept'
  --bind 'esc:abort'
)

# Preview pane layout (token column vs description); shared by RTFM + path merge + bare path pickers.
typeset -g __fzf_rtfm_fzf_preview_window='right,80%,wrap'

# Help popup (?) — pager script path; created once by __fzf_rtfm_ensure_help_script.
typeset -g __fzf_rtfm_help_script=

__fzf_rtfm_print_help() {
  cat <<'EOF'
RTFM — Read The Fuzzy Manual
Press q to close this help.

HOW TO USE
  Tab at the start of a line
    Complete a command from PATH / builtins. After the command is
    inserted (cmd ), the options/arguments picker opens.

  Tab after a command and a space
    Open fzf with man/--help options and arguments, plus files/dirs
    when the command takes paths. A token starting with - is options only.

  Typed directory (src/, /)
    List directories only (no man options). Tab into a non-empty
    directory to list its children (depth 1). Empty directory: insert
    with a trailing space for the next argument (e.g. mv /src /dst).

  cd / pushd
    -L/-P options, then directories only (no Tcl man cd noise).

  Special: ip, docker, sv (runit services after a verb via $SVDIR).

KEYS INSIDE FZF
  arrows / Ctrl-j / Ctrl-k   Move selection
  Left/Right or Ctrl-h/l     Scroll the preview pane
  Tab                        Non-empty directory: zoom into it (depth 1;
                             list child names only). File, option, or
                             empty directory: insert it and keep the
                             picker open for the next token.
  Enter                      Insert the current pick and return to the shell
                             (does not run the command).
  Esc                        Abort and leave the command line unchanged.
                             During Ctrl-f: cancel regex typing or clear filter.
  Alt-.                      Toggle hidden names (dotfiles). On by default.
                             (fzf cannot bind Ctrl-.)
  Ctrl-f                     Options/arguments view only: case-sensitive regex
                             search. Prompt becomes regex> ; type a pattern,
                             Enter filters the list to all matches. Then arrows
                             or n / N|p move the selection; typing further
                             fuzzy-refines the filtered list. Esc clears filter.
  ?                          Show this help (press q to close)
  type to filter             Fuzzy-filter the left (token) column
                             (also works after a Ctrl-f filter to refine)

PREVIEW
  Options/arguments: man/--help description
  Paths: ls -ld plus file contents (directories list children)

NOTES
  Wrappers (sudo, doas, command, …) are skipped so Tab sees the real command.
  Enter never runs the command — it only inserts onto the line.
EOF
}

__fzf_rtfm_ensure_help_script() {
  setopt localoptions noshwordsplit
  if [[ -n "$__fzf_rtfm_help_script" && -x "$__fzf_rtfm_help_script" ]]; then
    return 0
  fi
  __fzf_rtfm_help_script=$(mktemp "${TMPDIR:-/tmp}/fzf-rtfm-help.XXXXXX") || return 1
  {
    print -r '#!/bin/sh'
    print -r 'print_help() {'
    print -r 'cat <<'"'"'RTFM_HELP'"'"
    __fzf_rtfm_print_help
    print -r 'RTFM_HELP'
    print -r '}'
    print -r 'if command -v less >/dev/null 2>&1; then'
    print -r '  print_help | less -R'
    print -r 'elif command -v more >/dev/null 2>&1; then'
    print -r '  print_help | more'
    print -r 'else'
    print -r '  print_help'
    print -r '  printf "\n[press Enter] " > /dev/tty'
    print -r '  read -r _ < /dev/tty || true'
    print -r 'fi'
  } >"$__fzf_rtfm_help_script"
  command chmod +x "$__fzf_rtfm_help_script"
}

# Attach ? help to every shared fzf keymap (refresh script each source).
if [[ -n "$__fzf_rtfm_help_script" ]]; then
  command rm -f "$__fzf_rtfm_help_script" 2>/dev/null || true
  __fzf_rtfm_help_script=
fi
if __fzf_rtfm_ensure_help_script; then
  __fzf_rtfm_fzf_binds_preview+=(--bind "?:execute:$__fzf_rtfm_help_script")
  __fzf_rtfm_fzf_binds_preview_nav+=(--bind "?:execute:$__fzf_rtfm_help_script")
  __fzf_rtfm_fzf_binds_basic+=(--bind "?:execute:$__fzf_rtfm_help_script")
fi

# Cached preview script for mixed path/man picker (refreshed each source).
typeset -g __fzf_rtfm_preview_script=
__fzf_rtfm_ensure_preview_script() {
  setopt localoptions noshwordsplit
  if [[ -n "$__fzf_rtfm_preview_script" && -x "$__fzf_rtfm_preview_script" ]]; then
    return 0
  fi
  __fzf_rtfm_preview_script=$(mktemp "${TMPDIR:-/tmp}/fzf-rtfm-prev-c.XXXXXX") || return 1
  {
    print -r '#!/bin/sh'
    # Args: token, kind (m|f), optional desc-file (tok<TAB>m<TAB>desc).
    # Do not pass the full fzf line through $SHELL -c: docker/man text
    # contains quotes (Don't, 'table') that break zsh -c.
    print -r 'tok=$1'
    print -r 'kind=$2'
    print -r 'descfile=$3'
    print -r 'if [ "$kind" != f ]; then'
    print -r '  if [ -n "$descfile" ] && [ -f "$descfile" ]; then'
    print -r '    awk -F "\t" -v t="$tok" '\''$1==t { print $3; found=1 } END { exit !found }'\'' "$descfile" 2>/dev/null && exit 0'
    print -r '  fi'
    print -r '  exit 0'
    print -r 'fi'
    print -r 'ls -ld -- "$tok" 2>/dev/null'
    print -r 'if [ -d "$tok" ]; then'
    print -r '  printf "\n"'
    print -r '  ls -la -- "$tok" 2>/dev/null | head -n 80'
    print -r '  exit 0'
    print -r 'fi'
    print -r 'if [ ! -e "$tok" ] && [ ! -L "$tok" ]; then'
    print -r '  exit 0'
    print -r 'fi'
    print -r 'printf "\n"'
    print -r 'mime='
    print -r 'if command -v file >/dev/null 2>&1; then'
    print -r '  mime=$(file -b --mime-type -- "$tok" 2>/dev/null || true)'
    print -r 'fi'
    print -r 'case "$mime" in'
    print -r '  ""|text/*|*empty*|inode/x-empty|application/json|application/xml|application/javascript|application/x-sh|application/x-shellscript|application/x-csh|application/toml|application/yaml|application/x-yaml|application/sql)'
    print -r '    head -n 500 -- "$tok" 2>/dev/null'
    print -r '    ;;'
    print -r '  *)'
    print -r '    if command -v file >/dev/null 2>&1; then'
    print -r '      file -- "$tok" 2>/dev/null'
    print -r '    else'
    print -r '      printf "(binary or non-text file)\n"'
    print -r '    fi'
    print -r '    ;;'
    print -r 'esac'
  } >"$__fzf_rtfm_preview_script"
  command chmod +x "$__fzf_rtfm_preview_script"
}
if [[ -n "$__fzf_rtfm_preview_script" ]]; then
  command rm -f "$__fzf_rtfm_preview_script" 2>/dev/null || true
  __fzf_rtfm_preview_script=
fi
__fzf_rtfm_ensure_preview_script

# Write the in-fzf path lister. Field 1 is the name shown in fzf (basename
# after zoom); field 3 is the full path for preview/insert.
__fzf_rtfm_write_lister() {
  local out="$1" state="$2" manfile="$3" keep_dotslash="$4"
  {
    print -r '#!/bin/sh'
    print -r "statefile='$state'"
    print -r "manfile='$manfile'"
    print -r "keep_dotslash='$keep_dotslash'"
    print -r 'dir=$(sed -n "1p" "$statefile")'
    print -r 'hidden=$(sed -n "2p" "$statefile")'
    print -r 'depth=$(sed -n "3p" "$statefile")'
    print -r 'show_man=$(sed -n "4p" "$statefile")'
    print -r 'mode=$(sed -n "5p" "$statefile")'
    print -r '[ -n "$dir" ] || dir=.'
    print -r '[ -n "$hidden" ] || hidden=1'
    print -r '[ -n "$depth" ] || depth=1'
    print -r 'case "$depth" in'
    print -r '  *[!0-9]*|"") depth=1 ;;'
    print -r 'esac'
    print -r '[ -n "$show_man" ] || show_man=0'
    print -r '[ -n "$mode" ] || mode=all'
    print -r 'if [ "$show_man" = 1 ] && [ -s "$manfile" ]; then'
    print -r '  cat "$manfile"'
    print -r 'fi'
    print -r '[ -d "$dir" ] || exit 0'
    print -r 'if [ "$dir" = . ] || [ "$dir" = ./ ]; then'
    print -r $'  printf \'/\\tf\\t/\\n\''
    print -r 'fi'
    print -r 'if [ "$dir" = / ]; then'
    print -r '  if [ "$hidden" = 1 ]; then'
    print -r '    find / -mindepth 1 -maxdepth "$depth" \( -path /proc -o -path /sys -o -path /dev -o -path /run \) -prune -o \( -type d -o -type l \) -print'
    print -r '  else'
    print -r '    find / -mindepth 1 -maxdepth "$depth" \( -path /proc -o -path /sys -o -path /dev -o -path /run -o -name ".*" \) -prune -o \( -type d -o -type l \) -print'
    print -r '  fi'
    print -r 'elif [ "$hidden" = 1 ]; then'
    print -r '  if [ "$mode" = dirs ]; then'
    print -r '    find "$dir" -mindepth 1 -maxdepth "$depth" \( -type d -o -type l \)'
    print -r '  else'
    print -r '    find "$dir" -mindepth 1 -maxdepth "$depth" \( -type f -o -type d -o -type l \)'
    print -r '  fi'
    print -r 'else'
    print -r '  if [ "$mode" = dirs ]; then'
    print -r '    find "$dir" -mindepth 1 -maxdepth "$depth" \( -name ".*" -prune -o \( -type d -o -type l \) -print \)'
    print -r '  else'
    print -r '    find "$dir" -mindepth 1 -maxdepth "$depth" \( -name ".*" -prune -o \( -type f -o -type d -o -type l \) -print \)'
    print -r '  fi'
    print -r 'fi 2>/dev/null | sort | while IFS= read -r p; do'
    print -r '  [ -z "$p" ] && continue'
    print -r '  if { [ "$mode" = dirs ] || [ "$dir" = / ]; } && [ ! -d "$p" ]; then'
    print -r '    continue'
    print -r '  fi'
    print -r '  name=$p'
    print -r '  if [ "$dir" = . ] || [ "$dir" = ./ ]; then'
    print -r '    name=${p#./}'
    print -r '  fi'
    print -r '  case "$name" in'
    print -r '    .|..|*/.|*/..) continue ;;'
    print -r '  esac'
    print -r '  if [ "$keep_dotslash" = 1 ]; then'
    print -r '    case "$name" in'
    print -r '      ./*|/*) ;;'
    print -r '      *) name="./$name" ;;'
    print -r '    esac'
    print -r '  fi'
    print -r '  display=$name'
    print -r '  if [ "$dir" != . ] && [ "$dir" != ./ ]; then'
    print -r '    display=${name##*/}'
    print -r '    [ -n "$display" ] || display=$name'
    print -r '  fi'
    print -r $'  printf \'%s\\tf\\t%s\\n\' "$display" "$name"'
    print -r 'done'
  } >"$out"
}

# Write Tab transformer (optional searchstate/filterfile/promptfile for options view).
__fzf_rtfm_write_transformer() {
  local out="$1" state="$2" lister="$3" zoom_mode="$4"
  local searchstate="${5-}" filterfile="${6-}" promptfile="${7-}"
  {
    print -r '#!/bin/sh'
    print -r "statefile='$state'"
    print -r "lister='$lister'"
    print -r "zoom_mode='$zoom_mode'"
    [[ -n "$searchstate" ]] && print -r "searchstate='$searchstate'"
    [[ -n "$filterfile" ]] && print -r "filterfile='$filterfile'"
    [[ -n "$promptfile" ]] && print -r "promptfile='$promptfile'"
    print -r 'tok=$1'
    print -r 'dir=$(sed -n "1p" "$statefile")'
    print -r '[ -n "$dir" ] || dir=.'
    print -r 'if [ ! -d "$tok" ]; then'
    print -r '  case "$dir" in'
    print -r '    /) cand="/$tok" ;;'
    print -r '    .|./) cand="$tok" ;;'
    print -r '    *) cand="$dir/${tok#./}" ;;'
    print -r '  esac'
    print -r '  [ -d "$cand" ] && tok=$cand'
    print -r 'fi'
    print -r 'hidden=$(sed -n "2p" "$statefile")'
    print -r 'mode=$(sed -n "5p" "$statefile")'
    print -r '[ -n "$hidden" ] || hidden=1'
    print -r '[ -n "$mode" ] || mode=all'
    print -r '[ -n "$zoom_mode" ] || zoom_mode=all'
    print -r 'has_entries=0'
    print -r 'check_mode=$zoom_mode'
    print -r '[ -n "$check_mode" ] || check_mode=$mode'
    print -r 'if [ -d "$tok" ]; then'
    print -r '  if [ "$tok" = / ]; then'
    print -r '    if [ "$hidden" = 1 ]; then'
    print -r '      first=$(find / -mindepth 1 -maxdepth 1 \( -path /proc -o -path /sys -o -path /dev -o -path /run \) -prune -o \( -type d -o -type l \) -print 2>/dev/null | head -n 1)'
    print -r '    else'
    print -r '      first=$(find / -mindepth 1 -maxdepth 1 \( -path /proc -o -path /sys -o -path /dev -o -path /run -o -name ".*" \) -prune -o \( -type d -o -type l \) -print 2>/dev/null | head -n 1)'
    print -r '    fi'
    print -r '  elif [ "$check_mode" = dirs ]; then'
    print -r '    if [ "$hidden" = 1 ]; then'
    print -r '      first=$(find "$tok" -mindepth 1 -maxdepth 1 \( -type d -o -type l \) 2>/dev/null | head -n 1)'
    print -r '    else'
    print -r '      first=$(find "$tok" -mindepth 1 -maxdepth 1 \( -name ".*" -prune -o \( -type d -o -type l \) -print \) 2>/dev/null | head -n 1)'
    print -r '    fi'
    print -r '    [ -n "$first" ] && [ -d "$first" ] || first='
    print -r '  elif [ "$hidden" = 1 ]; then'
    print -r '    first=$(find "$tok" -mindepth 1 -maxdepth 1 \( -type f -o -type d -o -type l \) 2>/dev/null | head -n 1)'
    print -r '  else'
    print -r '    first=$(find "$tok" -mindepth 1 -maxdepth 1 \( -name ".*" -prune -o \( -type f -o -type d -o -type l \) -print \) 2>/dev/null | head -n 1)'
    print -r '  fi'
    print -r '  [ -n "$first" ] && has_entries=1'
    print -r 'fi'
    print -r 'if [ -d "$tok" ] && [ "$has_entries" = 1 ]; then'
    print -r '  { printf "%s\n" "$tok"; printf "%s\n" "$hidden"; printf "%s\n" 1; printf "%s\n" 0; printf "%s\n" "$zoom_mode"; } > "$statefile"'
    if [[ -n "$searchstate" ]]; then
      print -r '  : > "$searchstate"'
      print -r '  : > "$filterfile"'
    fi
    print -r '  if [ "$tok" = / ]; then zoom_base=/; else zoom_base=${tok##*/}/; fi'
    print -r '  [ -n "$zoom_base" ] || zoom_base=$tok'
    print -r '  zoom_hdr=$(printf %s "$zoom_base" | tr "()\n\t" "[]  ")'
    if [[ -n "$promptfile" ]]; then
      print -r '  printf "reload(%s)+clear-query+enable-search+unbind(n)+unbind(N)+unbind(p)+change-header()+change-prompt(%s > )\n" "$lister" "$zoom_hdr"'
    else
      print -r '  printf "reload(%s)+clear-query+unbind(n)+unbind(N)+unbind(p)+change-header()+change-prompt(%s > )\n" "$lister" "$zoom_hdr"'
    fi
    print -r 'else'
    print -r '  printf "accept\n"'
    print -r 'fi'
  } >"$out"
}

# Write Alt-. toggler; clears active Ctrl-f filter so listing stays consistent.
__fzf_rtfm_write_toggler() {
  local out="$1" state="$2" lister="$3" searchstate="${4-}" filterfile="${5-}"
  {
    print -r '#!/bin/sh'
    print -r "statefile='$state'"
    print -r "lister='$lister'"
    [[ -n "$searchstate" ]] && print -r "searchstate='$searchstate'"
    [[ -n "$filterfile" ]] && print -r "filterfile='$filterfile'"
    print -r 'dir=$(sed -n "1p" "$statefile")'
    print -r 'hidden=$(sed -n "2p" "$statefile")'
    print -r 'depth=$(sed -n "3p" "$statefile")'
    print -r 'show_man=$(sed -n "4p" "$statefile")'
    print -r 'mode=$(sed -n "5p" "$statefile")'
    print -r '[ -n "$dir" ] || dir=.'
    print -r '[ -n "$hidden" ] || hidden=1'
    print -r '[ -n "$depth" ] || depth=1'
    print -r '[ -n "$show_man" ] || show_man=0'
    print -r '[ -n "$mode" ] || mode=all'
    print -r 'if [ "$hidden" = 1 ]; then hidden=0; else hidden=1; fi'
    print -r '{ printf "%s\n" "$dir"; printf "%s\n" "$hidden"; printf "%s\n" "$depth"; printf "%s\n" "$show_man"; printf "%s\n" "$mode"; } > "$statefile"'
    if [[ -n "$searchstate" ]]; then
      print -r 'if [ -n "$(sed -n "1p" "$searchstate" 2>/dev/null)" ]; then'
      print -r '  : > "$searchstate"'
      print -r '  : > "$filterfile"'
      print -r '  printf "reload(%s)+clear-query+unbind(n)+unbind(N)+unbind(p)+change-header()\n" "$lister"'
      print -r 'else'
      print -r '  printf "reload(%s)\n" "$lister"'
      print -r 'fi'
    else
      print -r 'printf "reload(%s)\n" "$lister"'
    fi
  } >"$out"
}

# ZLE leaves the *parent* shell TTY non-canonical during widgets; fzf needs the real TTY cooked
# before its child runs. Subshell-only stty is not always enough — fix parent first, then restore.
__fzf_rtfm_zle_parent_tty_prepare() {
  typeset -g _RTFM_ZLE_STTY
  _RTFM_ZLE_STTY=$(command stty -g 2>/dev/null) || _RTFM_ZLE_STTY=
  command stty sane 2>/dev/null || true
  command stty isig icanon echo 2>/dev/null || true
}

__fzf_rtfm_zle_parent_tty_restore() {
  [[ -n ${_RTFM_ZLE_STTY-} ]] && command stty "$_RTFM_ZLE_STTY" 2>/dev/null || true
  unset _RTFM_ZLE_STTY
}

__fzf_resolve_binary() {
  local binary_name="$1"
  command -v -- "$binary_name" >/dev/null 2>&1 || {
    print -u2 "Binary $binary_name does not exist"
    return 1
  }
  command -v -- "$binary_name"
}

__fzf_man_topic_exists() {
  local topic="$1"
  command man -w "$topic" >/dev/null 2>&1
}

# Always force a non-interactive pager. Do not pass -P (mandoc has no -P;
# groff man honors MANPAGER/PAGER). stdin from /dev/null so man never
# touches the ZLE tty. Write through a temp file — avoid huge zsh scalars
# (xtrace / ${(z)} quote dumps show up above the 90%-height fzf window).
__fzf_rtfm_man_text() {
  local topic="$1" tmp
  [[ -n "$topic" ]] || return 1
  tmp=$(mktemp "${TMPDIR:-/tmp}/fzf-rtfm-man.XXXXXX") || return 1
  if ! PAGER=cat MANPAGER=cat GROFF_NO_SGR=1 command man "$topic" </dev/null 2>/dev/null \
      | command col -b >"$tmp"
  then
    command rm -f "$tmp"
    return 1
  fi
  [[ -s "$tmp" ]] || { command rm -f "$tmp"; return 1; }
  command cat "$tmp"
  local ec=$?
  command rm -f "$tmp"
  return $ec
}

__fzf_get_help_text() {
  # $1: binary name
  local binary_name="$1"
  local txt

  # Prefer `--help`, fall back to `-h`. PAGER=cat so help never blocks on a pager.
  txt=$(PAGER=cat MANPAGER=cat "$binary_name" --help 2>/dev/null) || true
  if [[ -z "$txt" ]]; then
    txt=$(PAGER=cat MANPAGER=cat "$binary_name" -h 2>/dev/null) || true
  fi
  # runit sv(8) often prints a one-line usage only on stderr when run with no args
  if [[ -z "$txt" && "$binary_name" == sv ]]; then
    txt="$(sv 2>&1)" || true
  fi

  # If we have nothing, return failure
  if [[ -z "$txt" ]]; then
    return 2
  fi

  # "usage:" or "usage " (some tools omit the colon)
  if ! print -r -- "$txt" | command rg -iq '(^|[[:space:]])usage[[:space:]:]'; then
    return 2
  fi

  printf '%s\n' "$txt"
}

__fzf_compact_ws() {
  # collapses multiple whitespace to single spaces (for descriptions)
  print -r -- "$1" | command awk '{$1=$1; print}'
}

# ---------- Parse options from a man page/help ----------
# Output format:
#   token<TAB>description
#
# User logic:
# - A line that has a word then starts with '-' or '--' (after optional leading spaces)
#   starts a new entry:
#   token = the '-'/'--' portion(s) on that line
#   description = text on that same line after token
# - Description continues on the next indented lines until the next '-'/'--' start line.
#
# This is best-effort across varied man/help formats.
# shellcheck disable=SC2120
# (call sites use stdin; optional $1 is for direct invocation)
__fzf_parse_dash_options_block() {
  # Reads from $1 when provided, otherwise reads from stdin.
  # This lets us use it both as:
  #   __fzf_parse_dash_options_block "$text"
  # and as:
  #   some_command | __fzf_parse_dash_options_block
  local text
  if [[ $# -ge 1 ]]; then
    text="$1"
  else
    text="$(</dev/stdin)"
  fi

  printf '%s\n' "$text" | awk '
    function is_blank(s) { return s ~ /^[[:space:]]*$/ }

    function is_footer(s) {
      # Stop before man trailers (AUTHOR/SEE ALSO often contain quotes that
      # must never land in fzf/shell strings).
      return s ~ /^[[:space:]]*(SEE ALSO|AUTHOR|AUTHORS|REPORTING BUGS|COPYRIGHT|COLOPHON|BUGS|FILES|ENVIRONMENT|HISTORY|STANDARDS|NOTES|EXAMPLES)([[:space:]]|$)/
    }

    function emit() {
      if (in_entry && token != "" ) {
        print token "\t" desc
      }
      in_entry = 0
      token = ""
      desc = ""
    }

    BEGIN { in_entry = 0; token=""; desc="" }

    is_footer($0) { emit(); exit }

    # Detect an option start line:
    # first non-space must be '-' followed by a non-space char.
    # This avoids matching man-help lines like "- protocol ..." (dash + space).
    /^[[:space:]]*-[^[:space:]]/ {
      # We must be careful to only treat "-" / "--" lines as option starts.
      # Docker/generic help frequently has lines that start with whitespace then "-".
      emit()

      in_entry = 1
      line = $0
      gsub(/^[[:space:]]+/, "", line)

      # Build token from the beginning of the line:
      # - include dash tokens (-x, --long, --long=<v> ...)
      # - optionally include a placeholder argument immediately following a dash token
      #   when the placeholder looks like "<...>" or "[<...>]".
      #
      # Description will be everything after the token.
      n = split(line, f, /[[:space:]]+/)
      token = ""
      desc = ""

      last_token_idx = 0
      i = 1
      while (i <= n) {
        if (f[i] ~ /^-/) {
          token = (token == "" ? f[i] : token " " f[i])
          last_token_idx = i

          # If the option is followed by a placeholder, include it too.
          if (i + 1 <= n && f[i+1] ~ /^[<\[]/) {
            token = token " " f[i+1]
            last_token_idx = i + 1
            i = i + 2
            continue
          }

          i = i + 1
          continue
        }

        # First non-dash word ends the token; rest is description.
        break
      }

      if (last_token_idx > 0 && last_token_idx < n) {
        for (j = last_token_idx + 1; j <= n; j++) {
          desc = (desc == "" ? f[j] : desc " " f[j])
        }
      } else {
        desc = ""
      }
      next
    }

    # Continuation lines: while inside entry, append indented lines (not another option start)
    {
      if (!in_entry) next
      if (is_blank($0)) next

      # New option start: emit previous entry, then re-process this line as a start.
      if ($0 ~ /^[[:space:]]*-[^[:space:]]/) {
        emit()
        in_entry = 0
        # Fall through by re-handling as option start (duplicate start logic below).
        n = split($0, f, /[[:space:]]+/)
        while (n > 0 && f[1] == "") {
          for (k = 1; k < n; k++) f[k] = f[k+1]
          n--
        }
        in_entry = 1
        token = ""
        desc = ""
        last_token_idx = 0
        i = 1
        while (i <= n) {
          if (f[i] ~ /^-/) {
            token = (token == "" ? f[i] : token " " f[i])
            last_token_idx = i
            if (i + 1 <= n && f[i+1] ~ /^[<\[]/) {
              token = token " " f[i+1]
              last_token_idx = i + 1
              i = i + 2
              continue
            }
            i = i + 1
            continue
          }
          break
        }
        if (last_token_idx > 0 && last_token_idx < n) {
          for (j = last_token_idx + 1; j <= n; j++) {
            desc = (desc == "" ? f[j] : desc " " f[j])
          }
        } else {
          desc = ""
        }
        next
      }

      l = $0
      gsub(/^[[:space:]]+/, "", l)
      if (l != "") {
        if (desc == "") desc = l
        else desc = desc " " l
      }
    }

    END { emit() }
  ' | awk 'NF' | sort -u
}

# ---------- Parse subcommands from a man `binary` page ----------
__fzf_parse_man_subcommands() {
  # $1: binary name
  local cmd="$1"

  # Using man -k "^cmd-" is robust (works for git)
  man -k "^${cmd}-" 2>/dev/null | awk '
    {
      name=$1
      gsub(/\(.*\)$/, "", name)
      sub("^" cmd "-", "", name)
      if (name == "") next

      idx = index($0, " - ")
      desc = (idx > 0 ? substr($0, idx + 3) : "")
      print name "\t" desc
    }
  ' cmd="$cmd" | awk 'NF' | sort -u
}

# ---------- docker parsing ----------
__fzf_docker_root_entries() {
  # Uses the parsing function you requested to keep existing behavior.
  docker --help 2>/dev/null | awk '
    BEGIN { section = "" }

    /^Common Commands:/      { section = "cmd"; next }
    /^Management Commands:/  { section = "cmd"; next }
    /^Swarm Commands:/       { section = "cmd"; next }
    /^Commands:/             { section = "cmd"; next }
    /^Global Options:/       { section = "opt"; next }

    section == "cmd" && /^[[:space:]]+[a-z][a-z0-9-]*[[:space:]]+/ {
      line = $0
      gsub(/^[[:space:]]+/, "", line)
      name = $1
      # remove name from line
      sub("^[^[:space:]]+[[:space:]]+", "", $0)
      gsub(/^[[:space:]]+/, "", $0)
      print name "\t" $0
      next
    }

    # Option-ish lines in docker help typically look like:
    #   --config string      Location of client config files ...
    section == "opt" {
      if ($0 ~ /^[[:space:]]*(-[A-Za-z],)?[[:space:]]*--/) {
        line = $0
        gsub(/^[[:space:]]+/, "", line)
        # split at 2+ spaces, token part = a[1]
        n = split(line, a, /[[:space:]]{2,}/)
        tok = a[1]
        desc = (n >= 2 ? a[2] : "")
        # Choose a representative token: prefer --long if present
        nt = split(tok, t, /[[:space:]]+/)
        keep=""
        for (i=1; i<=nt; i++) {
          if (t[i] ~ /^--/) { keep=t[i]; break }
        }
        if (keep == "" && nt >= 1) keep = t[1]
        if (keep != "") print keep "\t" desc
      }
    }
  ' | awk 'NF' | sort -u
}

__fzf_docker_sub_options() {
  # $1: docker subcommand
  local sub="$1"

  docker "$sub" --help 2>/dev/null | awk '
    /^Options:/ { inopts=1; next }
    inopts && /^[[:space:]]*$/ { next }

    inopts {
      # detect option lines (start with whitespace then "-" or "--")
      if ($0 ~ /^[[:space:]]+(-|--)/) {
        line = $0
        gsub(/^[[:space:]]+/, "", line)
        n = split(line, a, /[[:space:]]{2,}/)
        optpart = a[1]
        desc = (n >= 2 ? a[2] : "")

        # Split comma-separated options into separate tokens:
        m = split(optpart, t, /[[:space:]]*,[[:space:]]*/)
        for (i = 1; i <= m; i++) {
          opt=t[i]
          gsub(/^[[:space:]]+|[[:space:]]+$/, "", opt)
          if (opt != "") print opt "\t" desc
        }
      }
    }
  ' | awk 'NF' | sort -u
}

# ---------- ip parsing (iproute2 is special) ----------
# ip(8): global "OPTIONS" are only in one section; the rest of the page mixes
# OBJECT prose ("- protocol …") and synopsis lines that look like options but are not.
# Per-object pages ip-<object>(8): same idea — parse the OPTIONS section + synopsis verbs.

__fzf_ip_man_colb() {
  # $1: man topic, default ip
  local topic="${1:-ip}"
  __fzf_rtfm_man_text "$topic"
}

# Pull multi-line "OBJECT := { a | b | ... }" from ip(8) synopsis.
__fzf_ip_synopsis_object_names() {
  __fzf_ip_man_colb ip | awk '
    function trim(s) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
      return s
    }
    /OBJECT :=/ {
      buf = $0
      while (buf !~ /\}/ && (getline line) > 0) buf = buf " " line
      start = index(buf, "{")
      end = index(buf, "}")
      if (start > 0 && end > start) {
        inner = substr(buf, start + 1, end - start - 1)
        n = split(inner, a, /\|/)
        for (i = 1; i <= n; i++) {
          tok = trim(a[i])
          if (tok != "") print tok
        }
      }
      exit
    }
  ' | awk 'NF' | sort -u
}

# Map CLI token -> canonical OBJECT name from the synopsis list (prefix match).
__fzf_ip_canonical_object() {
  local sub="$1"
  [[ -z "$sub" ]] && return 1

  local objs best="" best_len=0 o len
  objs="$(__fzf_ip_synopsis_object_names)" || return 1

  while IFS= read -r o; do
    [[ -z "$o" ]] && continue
    if [[ "$o" == "$sub" ]]; then
      printf '%s\n' "$o"
      return 0
    fi
    if [[ "$o" == "$sub"* ]]; then
      len=${#o}
      if (( best_len == 0 || len < best_len )); then
        best="$o"
        best_len=$len
      fi
    fi
  done <<< "$objs"

  [[ -n "$best" ]] && { printf '%s\n' "$best"; return 0; }
  printf '%s\n' "$sub"
}

# Resolve man page topic for an OBJECT (synopsis uses neighbor; system may ship ip-neighbour only).
__fzf_ip_resolve_man_topic() {
  local o="$1"
  local cands=(
    "ip-$o"
    "ip-${o//_/-}"
  )
  # common alternates
  case "$o" in
    neighbor) cands+=(ip-neighbour) ;;
    neighbour) cands+=(ip-neighbor) ;;
    ntbl) cands+=(ip-ntable) ;;
    tcpmetrics) cands+=(ip-tcp_metrics) ;;
  esac

  local t
  for t in "${cands[@]}"; do
    __fzf_man_topic_exists "$t" || continue
    printf '%s\n' "$t"
    return 0
  done
  return 1
}

# Extract only the body of the OPTIONS section (iproute2 man pages: section title "OPTIONS").
__fzf_ip_extract_options_section() {
  # stdin: full man text (col -b); stdout: OPTIONS section only
  awk '
    function is_stop(l) {
      if (l ~ /^[[:space:]]*SEE ALSO[[:space:]]/) return 1
      if (l ~ /^[[:space:]]*EXAMPLES[[:space:]]/) return 1
      if (l ~ /^[[:space:]]*ENVIRONMENT[[:space:]]/) return 1
      if (l ~ /^[[:space:]]*EXIT STATUS[[:space:]]/) return 1
      if (l ~ /^[[:space:]]*AUTHOR[[:space:]]/) return 1
      if (l ~ /^[[:space:]]*COLOPHON[[:space:]]/) return 1
      if (l ~ /^[[:space:]]*REPORTING BUGS[[:space:]]/) return 1
      if (l ~ /^[[:space:]]*HISTORY[[:space:]]/) return 1
      # ip(8) leaves OPTIONS before this narrative block
      if (l ~ /^[[:space:]]*IP - COMMAND SYNTAX[[:space:]]/) return 1
      # ip-link(8) etc.: further chapters are titled "IP LINK …" (not dash options)
      if (l ~ /^[[:space:]]*IP [[:upper:]]/) return 1
      return 0
    }

    /^[[:space:]]*OPTIONS([[:space:]]|$)/ {
      in_section = 1
      next
    }
    in_section && is_stop($0) {
      exit
    }
    in_section {
      print
    }
  '
}

# Optional one-line descriptions from the "IP - COMMAND SYNTAX" OBJECT list in ip(8).
__fzf_ip_object_blurbs_from_syntax() {
  __fzf_ip_man_colb ip | awk '
    function trim(s) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
      return s
    }
    /^[[:space:]]*IP - COMMAND SYNTAX[[:space:]]/ { in_doc = 1; next }
    in_doc && /^[[:space:]]*OBJECT[[:space:]]*$/ { in_obj = 1; next }
    in_doc && in_obj && /^[[:space:]]*COMMAND[[:space:]]*$/ { exit }
    in_doc && in_obj {
      if ($0 ~ /^[[:space:]]*[a-z][a-z0-9_-]*\/[a-z]/) next
      line = $0
      if (line ~ /^[[:space:]]+[a-z][a-z0-9_-]*[[:space:]]*$/) {
        pending_name = trim(line)
        next
      }
      if (pending_name != "" && line ~ /^[[:space:]]+-[[:space:]]+/) {
        sub(/^[[:space:]]+-[[:space:]]+/, "", line)
        print pending_name "\t" trim(line)
        pending_name = ""
      }
    }
  '
}

__fzf_ip_root_entries() {
  local objs blurbs manfull opts_txt opts_parsed combined

  objs="$(__fzf_ip_synopsis_object_names)" || return 1
  blurbs="$(__fzf_ip_object_blurbs_from_syntax)" || true
  manfull="$(__fzf_ip_man_colb ip)" || return 1

  opts_txt="$(print -r -- "$manfull" | __fzf_ip_extract_options_section)" || true
  opts_parsed=""
  [[ -n "$opts_txt" ]] && opts_parsed="$(print -r -- "$opts_txt" | __fzf_parse_dash_options_block)" || true

  combined="$(
    {
      while IFS= read -r name; do
        [[ -z "$name" ]] && continue
        d="$(printf '%s\n' "$blurbs" | awk -F'\t' -v n="$name" '$1==n{print $2; exit}')"
        [[ -z "$d" ]] && d="IP object"
        printf '%s\t%s\n' "$name" "$d"
      done <<< "$objs"
      [[ -n "$opts_parsed" ]] && printf '%s\n' "$opts_parsed"
    } | awk 'NF { if (!seen[$0]++) print }'
  )"

  [[ -z "$combined" ]] && return 1
  printf '%s\n' "$combined"
}

# Extract "verbs" from synopsis lines: { add | delete | help } (may appear multiple times).
__fzf_ip_extract_synopsis_verbs() {
  awk '
    function trim(s) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
      return s
    }
    /^[[:space:]]*SYNOPSIS([[:space:]]|$)/ { in_syn = 1; next }
    in_syn && /^[[:space:]]*DESCRIPTION([[:space:]]|$)/ { exit }
    in_syn {
      line = $0
      # pick braced groups that look like command lists
      while (match(line, /\{([^}]+)\}/)) {
        inner = substr(line, RSTART + 1, RLENGTH - 2)
        line = substr(line, RSTART + RLENGTH)
        if (inner ~ /\|/) {
          n = split(inner, a, /\|/)
          for (i = 1; i <= n; i++) {
            w = trim(a[i])
            # drop bracketed clauses like "show [ dev … ]" -> need first word only
            sub(/\[.*/, "", w)
            w = trim(w)
            split(w, b, /[[:space:]]+/)
            verb = b[1]
            if (verb ~ /^[a-zA-Z][a-zA-Z0-9_-]*$/ && length(verb) <= 32)
              print verb "\t" "ip command"
          }
        }
      }
    }
  ' | awk 'NF { if (!seen[$0]++) print }'
}

__fzf_ip_submanual_entries() {
  local object="$1"
  local canon topic manfull opts_txt verbs_txt

  canon="$(__fzf_ip_canonical_object "$object")" || return 1
  topic="$(__fzf_ip_resolve_man_topic "$canon")" || return 1

  manfull="$(__fzf_ip_man_colb "$topic")" || return 1
  opts_txt="$(print -r -- "$manfull" | __fzf_ip_extract_options_section)" || true
  verbs_txt="$(print -r -- "$manfull" | __fzf_ip_extract_synopsis_verbs)" || true

  local opts_parsed=""
  [[ -n "$opts_txt" ]] && opts_parsed="$(print -r -- "$opts_txt" | __fzf_parse_dash_options_block)" || true

  {
    [[ -n "$verbs_txt" ]] && printf '%s\n' "$verbs_txt"
    [[ -n "$opts_parsed" ]] && printf '%s\n' "$opts_parsed"
  } | awk 'NF { if (!seen[$0]++) print }'
}

# ---------- sv (runit) ----------
# Usage: sv [options] command services...
# Options come first (-v, -w sec); then a command verb; then one or more service names.
# The service name is whatever you already typed on the line; the widget only appends tokens.
__fzf_sv_runit_command_rows() {
  # One token per line = the *command* (after any options). Then you add service(s).
  cat <<'EOF'
check	check (after options); then service name(s)
cont	cont — continue; then service name(s)
d	down — same as down; then service name(s)
down	down — stop restarting; then service name(s)
exit	exit — TERM supervise; then service name(s)
help	help — per-service help; then service name(s)
hup	hup; then service name(s)
once	once — run once; then service name(s)
o	same as once; then service name(s)
pause	pause; then service name(s)
quit	quit; then service name(s)
q	same as quit; then service name(s)
reload	reload; then service name(s)
restart	restart; then service name(s)
status	status — default; then service name(s)
s	same as status; then service name(s)
shutdown	shutdown; then service name(s)
start	start — often same as up; then service name(s)
stop	stop; then service name(s)
term	term; then service name(s)
t	same as term; then service name(s)
try	try; then service name(s)
up	up — start if down; then service name(s)
u	same as up; then service name(s)
EOF
}

__fzf_sv_usage_line() {
  local manfull line
  manfull="$(__fzf_rtfm_man_text sv)"
  line="$(print -r -- "$manfull" | command rg -m1 -i 'usage:' || true)"
  if [[ -z "$line" ]]; then
    if command -v timeout >/dev/null 2>&1; then
      line="$(timeout 1 sv 2>&1 | awk 'NR==1{print; exit}')" || true
    else
      line="$(sv 2>&1 | awk 'NR==1{print; exit}')" || true
    fi
  fi
  print -r -- "$line"
}

__fzf_sv_entries() {
  local manfull opts opts_help usage_line opts_syn combined
  manfull="$(__fzf_rtfm_man_text sv)"

  opts=""
  if [[ -n "$manfull" ]]; then
    opts="$(print -r -- "$manfull" | __fzf_ip_extract_options_section | __fzf_parse_dash_options_block)" || true
  fi

  opts_help=""
  if command -v timeout >/dev/null 2>&1; then
    opts_help="$(timeout 2 sv --help 2>&1)" || true
  else
    opts_help="$(sv --help 2>&1)" || true
  fi
  if [[ -z "$opts_help" ]]; then
    if command -v timeout >/dev/null 2>&1; then
      opts_help="$(timeout 2 sv -h 2>&1)" || true
    else
      opts_help="$(sv -h 2>&1)" || true
    fi
  fi
  if [[ -n "$opts_help" ]]; then
    opts_help="$(print -r -- "$opts_help" | __fzf_parse_dash_options_block)" || true
  else
    opts_help=""
  fi

  usage_line="$(__fzf_sv_usage_line)"
  opts_syn=""
  if print -r -- "$usage_line" | command rg -iq '\[-v\]'; then
    opts_syn+=$'\n-v\tsv option (before command): verbose'
  fi
  if print -r -- "$usage_line" | command rg -iq '\[-w'; then
    opts_syn+=$'\n-w\tsv option (before command): wait timeout; type as -w then a number, e.g. -w 5'
  fi

  # Order: [parameters/options first] then [command verbs] — matches: sv [options] command service…
  combined="$(
    {
      [[ -n "$opts_syn" ]] && printf '%s\n' "$opts_syn"
      [[ -n "$opts" ]] && printf '%s\n' "$opts"
      [[ -n "$opts_help" ]] && printf '%s\n' "$opts_help"
      __fzf_sv_runit_command_rows
    } | awk -F'\t' 'NF {
        key = $1
        if (!seen[key]++) print
      }'
  )"
  [[ -z "$combined" ]] && return 1
  printf '%s\n' "$combined"
}

# After `sv [options] COMMAND`, next tokens are service name(s) under $SVDIR (default /service or /var/service).
__fzf_sv_is_verb() {
  case "$1" in
    check|cont|d|down|exit|help|hup|once|o|pause|q|quit|reload|restart|status|s|shutdown|start|stop|term|t|try|up|u) return 0 ;;
    *) return 1 ;;
  esac
}

# True if the full command line already has a runit verb (e.g. check) so fzf should list services.
# Skips leading wrappers (sudo, doas, …) the same way as __fzf_get_cmd_and_sub.
__fzf_sv_should_offer_services() {
  local line="$1"
  [[ -z "$line" ]] && return 1
  setopt localoptions noshwordsplit
  local -a words
  words=("${(@f)$( __fzf_rtfm_wsplit "$line" )}")
  (( ${#words} >= 2 )) || return 1
  local start_idx=1
  while (( start_idx <= ${#words} )) && __fzf_rtfm_is_wrapper "${words[start_idx]}"; do
    (( start_idx++ ))
  done
  (( start_idx <= ${#words} )) || return 1
  [[ "${words[start_idx]}" == sv ]] || return 1
  local i=$(( start_idx + 1 )) found_verb=0
  while (( i <= ${#words} )); do
    local w="${words[i]}"
    case "$w" in
      -v)
        (( i++ ))
        ;;
      -w)
        (( i++ ))
        if (( i <= ${#words} )) && [[ "${words[i]}" =~ ^[0-9]+$ ]]; then
          (( i++ ))
        fi
        ;;
      -*)
        if [[ "$w" =~ ^-w[0-9]+$ ]]; then
          (( i++ ))
        else
          (( i++ ))
        fi
        ;;
      *)
        __fzf_sv_is_verb "$w" || return 1
        found_verb=1
        break
        ;;
    esac
  done
  (( found_verb ))
}

__fzf_sv_service_entries() {
  local svdir="${SVDIR:-/service}"
  [[ -d "$svdir" ]] || svdir="/var/service"
  [[ -d "$svdir" ]] || return 1

  setopt localoptions nullglob
  local -a names
  names=("$svdir"/*(N:t))
  (( ${#names} > 0 )) || return 1

  # Sorted, stable
  names=(${(i)names})
  local name
  for name in "${names[@]}"; do
    [[ -n "$name" ]] || continue
    print -r -- "$name	runit service under ${svdir}"
  done
}

# ---------- Decide how to interpret the current line ----------
__fzf_rtfm_is_wrapper() {
  case "$1" in
    sudo|doas|command|builtin|env|time|nice|nohup) return 0 ;;
  esac
  return 1
}

# Split a command line into words without ${(z)} — unmatched quotes in a
# token must not print a zsh parse dump above the 90%-height fzf UI.
__fzf_rtfm_wsplit() {
  setopt localoptions noshwordsplit
  local __s="$1"
  local -a __w
  __w=("${(s: :)__s}")
  __w=("${__w[@]:#}")
  print -r -- "${(F)__w}"
}

__fzf_get_cmd_and_sub() {
  # cmd = first real command after wrappers; sub = first non-option word after cmd
  setopt localoptions noshwordsplit

  local -a words
  words=("${(@f)$( __fzf_rtfm_wsplit "$LBUFFER" )}")
  (( ${#words} == 0 )) && return 1

  local start_idx=1
  while (( start_idx <= ${#words} )) && __fzf_rtfm_is_wrapper "${words[start_idx]}"; do
    (( start_idx++ ))
  done
  (( start_idx <= ${#words} )) || return 1

  local cmd="${words[start_idx]}"
  local sub=""
  local i
  for (( i = start_idx + 1; i <= ${#words}; i++ )); do
    [[ "${words[i]}" == -* ]] && continue
    sub="${words[i]}"
    break
  done

  printf '%s\t%s\n' "$cmd" "$sub"
}

# Prefer OPTIONS section from a man topic; fall back to full-page dash parse.
# Man page is kept on disk only — never assigned to a zsh scalar.
__fzf_rtfm_man_options_from_topic() {
  local topic="$1" tmp opts
  [[ -n "$topic" ]] || return 1
  tmp=$(mktemp "${TMPDIR:-/tmp}/fzf-rtfm-manpage.XXXXXX") || return 1
  if ! PAGER=cat MANPAGER=cat GROFF_NO_SGR=1 command man "$topic" </dev/null 2>/dev/null \
      | command col -b >"$tmp"
  then
    command rm -f "$tmp"
    return 1
  fi
  [[ -s "$tmp" ]] || { command rm -f "$tmp"; return 1; }
  opts="$(command awk '
    /^[[:space:]]*OPTIONS([[:space:]]|$)/ { in_opt = 1; next }
    in_opt && /^[[:space:]]*(SEE ALSO|AUTHOR|AUTHORS|REPORTING BUGS|COPYRIGHT|COLOPHON|BUGS|EXIT STATUS|EXIT VALUES|ENVIRONMENT|FILES|HISTORY|STANDARDS|NOTES)([[:space:]]|$)/ { exit }
    in_opt { print }
  ' "$tmp" | __fzf_parse_dash_options_block)" || opts=""
  if [[ -z "$opts" ]]; then
    opts="$(command cat "$tmp" | __fzf_parse_dash_options_block)" || opts=""
  fi
  command rm -f "$tmp"
  [[ -n "$opts" ]] || return 1
  printf '%s\n' "$opts"
}

# Cache parsed entries so Tab-continue does not re-run man (avoids the
# 90%-height gap above fzf filling with man/quote noise).
typeset -gA __fzf_rtfm_entry_cache

__fzf_build_entries_cached() {
  setopt localoptions noxtrace noverbose
  local cmd="$1" sub="$2" full="${3-}" key e
  # sv depends on the full line / $SVDIR — do not cache.
  if [[ "$cmd" == sv ]]; then
    __fzf_build_entries "$cmd" "$sub" "$full"
    return $?
  fi
  key="${cmd}"$'\t'"${sub}"
  if [[ -n "${__fzf_rtfm_entry_cache[$key]-}" ]]; then
    print -r -- "${__fzf_rtfm_entry_cache[$key]}"
    return 0
  fi
  e="$(__fzf_build_entries "$cmd" "$sub" "$full" 2>/dev/null)" || return $?
  [[ -n "$e" ]] || return 1
  __fzf_rtfm_entry_cache[$key]="$e"
  print -r -- "$e"
}

# ---------- Build entries (token<TAB>description) ----------
__fzf_build_entries() {
  # $1: cmd
  # $2: sub (may be empty)
  # $3: optional full command line (LBUFFER+RBUFFER) for context; needed for sv service picking
  local cmd="$1"
  local sub="$2"
  local full_line="${3:-}"

  # Special handling for ip, sv (runit), docker
  if [[ "$cmd" == ip ]]; then
    if __fzf_is_empty "$sub"; then
      __fzf_ip_root_entries || return 1
      return 0
    else
      # Prefer OBJECT man page; if sub is not an object (e.g. a verb), try resolving
      # the first non-flag word after ip from the full line as the OBJECT.
      if __fzf_ip_submanual_entries "$sub"; then
        return 0
      fi
      if [[ -n "$full_line" ]]; then
        setopt localoptions noshwordsplit
        local -a _ipw
        _ipw=("${(@f)$( __fzf_rtfm_wsplit "$full_line" )}")
        local _i=1 _obj=""
        while (( _i <= ${#_ipw} )) && __fzf_rtfm_is_wrapper "${_ipw[_i]}"; do
          ((_i++))
        done
        ((_i++)) # skip ip
        while (( _i <= ${#_ipw} )); do
          [[ "${_ipw[_i]}" == -* ]] && { ((_i++)); continue; }
          _obj="${_ipw[_i]}"
          break
        done
        if [[ -n "$_obj" && "$_obj" != "$sub" ]]; then
          __fzf_ip_submanual_entries "$_obj" || return 1
          return 0
        fi
      fi
      return 1
    fi
  fi

  # sv: [options] COMMAND service… — after COMMAND, offer service names from $SVDIR
  if [[ "$cmd" == sv ]]; then
    if [[ -n "$full_line" ]] && __fzf_sv_should_offer_services "$full_line"; then
      __fzf_sv_service_entries || __fzf_sv_entries || return 1
    else
      __fzf_sv_entries || return 1
    fi
    return 0
  fi

  if [[ "$cmd" == docker ]]; then
    if __fzf_is_empty "$sub"; then
      __fzf_docker_root_entries
      return 0
    else
      # Prefer man docker-SUB when present; else docker SUB --help (no root fallback).
      local opts
      if __fzf_man_topic_exists "docker-${sub}"; then
        opts="$(__fzf_rtfm_man_options_from_topic "docker-${sub}")" || opts=""
        if [[ -n "$opts" ]]; then
          printf '%s\n' "$opts"
          return 0
        fi
      fi
      opts="$(__fzf_docker_sub_options "$sub")" || opts=""
      [[ -n "$opts" ]] || return 1
      printf '%s\n' "$opts"
      return 0
    fi
  fi

  # Generic logic: man-first, else help
  if __fzf_is_empty "$sub"; then
    # root command: if man exists, show sub-man topics (binary-*) + options from binary man
    if __fzf_man_topic_exists "$cmd"; then
      local subs opts topic merged
      topic="$cmd"
      subs="$(__fzf_parse_man_subcommands "$cmd")" || true
      opts="$(__fzf_rtfm_man_options_from_topic "$topic")" || opts=""
      merged="$(printf '%s\n%s\n' "$subs" "$opts" | awk 'NF' | sort -u)"
      if [[ -n "$merged" ]]; then
        printf '%s\n' "$merged"
        return 0
      fi
    fi

    # no man, or man produced nothing the dash-parser understood (common for sv, etc.)
    local help_txt
    help_txt="$(__fzf_get_help_text "$cmd")" || {
      print -u2 "Binary $cmd has no manual or help."
      return 2
    }
    printf '%s\n' "$help_txt" | __fzf_parse_dash_options_block | awk 'NF' | sort -u
    return 0
  else
    # sub is present: treat as binary-sub for sub-man (binary-sub). If no man, fall back to binary sub help.
    local topic="${cmd}-${sub}"
    if __fzf_man_topic_exists "$topic"; then
      __fzf_rtfm_man_options_from_topic "$topic" && return 0
    fi

    # no sub-man: use help from "$cmd $sub --help" (best effort)
    local help_txt
    help_txt=$(PAGER=cat MANPAGER=cat "$cmd" "$sub" --help 2>/dev/null) || true
    if [[ -z "$help_txt" ]]; then
      help_txt=$(PAGER=cat MANPAGER=cat "$cmd" "$sub" -h 2>/dev/null) || true
    fi

    if [[ -z "$help_txt" ]]; then
      print -u2 "Binary $cmd has no manual or help."
      return 2
    fi
    if ! print -r -- "$help_txt" | command rg -iq '(^|[[:space:]])usage[[:space:]:]'; then
      print -u2 "Binary $cmd has no manual or help."
      return 2
    fi

    printf '%s\n' "$help_txt" | __fzf_parse_dash_options_block | awk 'NF' | sort -u
    return 0
  fi
}

# True when $2 appears as a finished root token (exact name, unique prefix,
# or a well-known iproute2 alias). Used so `ip addr` / `ip li` count as objects
# while `ip a` stays a filter query.
__fzf_rtfm_root_token_known() {
  local root_e="$1" sub="$2" cmd="${3-}"
  [[ -n "$sub" ]] || return 1
  if [[ -z "$root_e" ]]; then
    [[ -n "$cmd" ]] && __fzf_man_topic_exists "${cmd}-${sub}"
    return $?
  fi
  if [[ "$cmd" == ip ]]; then
    case "$sub" in
      addr) sub=address ;;
      neigh) sub=neighbour ;;
    esac
  fi
  print -r -- "$root_e" | command awk -F '\t' -v s="$sub" '
    $1 == s { exact = 1 }
    index($1, s) == 1 { n++ }
    END { exit !(exact || n == 1) }
  '
}

# True when the current token is a finished subcommand, not an incomplete
# prefix. Used to keep `sub` and clear the fzf query so option tokens
# (e.g. docker ps → --all) are not hidden by fuzzy-matching the sub name.
# Incomplete prefixes (docker p, git sta, sv sta, ip a, podman p) stay as
# the query against the root list.
__fzf_rtfm_sub_token_complete() {
  local cmd="$1" sub="$2" lastw="$3" full="${4-}"
  [[ -n "$sub" && "$lastw" == "$sub" && "$lastw" != -* ]] || return 1

  local sub_e root_e
  root_e="$(__fzf_build_entries "$cmd" "" "$full" 2>/dev/null)" || root_e=""
  __fzf_rtfm_root_token_known "$root_e" "$sub" "$cmd" || return 1

  sub_e="$(__fzf_build_entries "$cmd" "$sub" "$full" 2>/dev/null)" || return 1
  [[ -n "$sub_e" ]] || return 1
  # sv (and similar) always emit the root verb list for any token; that is
  # not a real sub page.
  [[ "$sub_e" != "$root_e" ]]
}

# ---------- Diagnostic: probe how a command exposes docs (man / help / stderr) ----------
# After sourcing this file, run:  fzf_diagnose_cmd git
# or:                         __fzf_diagnose_cmd sv
__fzf_diagnose_cmd() {
  local name="$1"
  if [[ -z "$name" ]]; then
    print -u2 "usage: __fzf_diagnose_cmd <command-name>"
    return 2
  fi

  local -a to_cmd
  if command -v timeout >/dev/null 2>&1; then
    to_cmd=(timeout 3)
  else
    to_cmd=()
  fi

  print -r -- "=== fzf-man-opts diagnostic: ${name} ==="
  print -r -- ""

  if ! command -v -- "$name" >/dev/null 2>&1; then
    print -r -- "[PATH] NOT FOUND (not in PATH as an executable)"
    print -r -- "=== end ==="
    return 1
  fi

  print -r -- "[PATH] $(command -v -- "$name")"
  print -r -- "[TYPE] $(whence -v "$name" 2>/dev/null || print -r -- "unknown")"
  print -r -- ""

  if __fzf_man_topic_exists "$name"; then
    print -r -- "[MAN] main: $(man -w "$name" 2>/dev/null)"
  else
    print -r -- "[MAN] main: (none)"
  fi

  local subk
  subk="$(man -k "^${name}-" 2>/dev/null)"
  if [[ -n "$subk" ]]; then
    local scnt
    scnt="$(print -r -- "$subk" | awk 'END{print NR+0}')"
    print -r -- "[MAN] sub-pages (man -k ^${name}-): count=${scnt}, first 15:"
    print -r -- "$subk" | awk 'NR<=15{print "    " $0}'
  else
    print -r -- "[MAN] sub-pages: (none for ^${name}-)"
  fi
  print -r -- ""

  if __fzf_man_topic_exists "$name"; then
    print -r -- "[MAN] excerpt (col -b, first 28 lines):"
    __fzf_rtfm_man_text "$name" | awk 'NR<=28{print "    " $0}'
  else
    print -r -- "[MAN] excerpt: skipped"
  fi
  print -r -- ""

  if __fzf_man_topic_exists "$name"; then
    local nparse
    nparse="$(__fzf_rtfm_man_text "$name" | __fzf_parse_dash_options_block 2>/dev/null | awk 'END{print NR+0}')"
    print -r -- "[PARSE] __fzf_parse_dash_options_block (full man page): ${nparse} entries"
  else
    print -r -- "[PARSE] (skipped, no main man page)"
  fi
  print -r -- ""

  print -r -- "[HELP] --help (3s timeout if timeout(1) exists):"
  if (( ${#to_cmd} )); then
    "${to_cmd[@]}" "$name" --help 2>&1 | awk 'NR<=10{print "    " $0}'
  else
    "$name" --help 2>&1 | awk 'NR<=10{print "    " $0}'
  fi
  print -r -- ""

  print -r -- "[HELP] -h:"
  if (( ${#to_cmd} )); then
    "${to_cmd[@]}" "$name" -h 2>&1 | awk 'NR<=10{print "    " $0}'
  else
    "$name" -h 2>&1 | awk 'NR<=10{print "    " $0}'
  fi
  print -r -- ""

  print -r -- "[HELP] no argv (stderr; 2s timeout if available):"
  if command -v timeout >/dev/null 2>&1; then
    timeout 2 "$name" 2>&1 | awk 'NR<=10{print "    " $0}'
  else
    "$name" 2>&1 | awk 'NR<=10{print "    " $0}'
  fi
  print -r -- ""

  print -r -- "[PLUGIN] __fzf_get_help_text:"
  local hblob
  if hblob="$(__fzf_get_help_text "$name" 2>/dev/null)"; then
    local hlines
    hlines="$(print -r -- "$hblob" | awk 'END{print NR+0}')"
    print -r -- "    OK, ${hlines} line(s), usage-pattern matched"
  else
    print -r -- "    FAIL (no usable help text by plugin rules)"
  fi
  print -r -- ""

  print -r -- "[PLUGIN] __fzf_build_entries \"${name}\" \"\" (stderr muted):"
  local entries ecnt
  entries="$({ __fzf_build_entries "$name" ""; } 2>/dev/null)" || true
  ecnt="$(print -r -- "$entries" | awk 'NF { c++ } END { print c+0 }')"
  print -r -- "    ${ecnt} row(s) — 0 often means man/help shape needs a special case"
  if (( ecnt > 0 )); then
    print -r -- "    sample:"
    print -r -- "$entries" | awk 'NF && NR<=5 { print "      " $0 }'
  fi
  print -r -- ""

  print -r -- "[HINT] current widget handling:"
  case "$name" in
    ip) print -r -- "    branch: ip (OBJECT + OPTIONS section + ip-<object> pages)" ;;
    docker) print -r -- "    branch: docker (docker --help / docker SUB --help; no root fallback on bad sub)" ;;
    sv)
      print -r -- "    branch: sv (OPTIONS+verbs, then services from \$SVDIR or /var/service when line has a verb)"
      print -r -- "    sv status  → services? $(__fzf_sv_should_offer_services 'sv status' && print yes || print no)"
      print -r -- "    sudo sv status → services? $(__fzf_sv_should_offer_services 'sudo sv status' && print yes || print no)"
      print -r -- "    SVDIR=${SVDIR-unset}"
      ;;
    *) print -r -- "    branch: generic (man OPTIONS section + man -k; else help)" ;;
  esac
  print -r -- "    --scheme path opts: ${(j: :)__fzf_rtfm_merged_path_scheme:-(none)}"
  print -r -- ""
  print -r -- "=== end ==="
}

fzf_diagnose_cmd() {
  __fzf_diagnose_cmd "$@"
}

# Paste full output when asking for help (typing in fzf query does not show).
fzf_rtfm_diagnose() {
  emulate -L zsh
  print -r -- "=== fzf-rtfm / Tab widget environment ==="
  print -r -- "zsh:              $ZSH_VERSION"
  print -r -- "fzf binary:       $(command -v fzf 2>/dev/null || print 'MISSING')"
  print -r -- "fzf --version:    $(command fzf --version 2>/dev/null || print n/a)"
  print -r -- "fzf-tmux:         $(command -v fzf-tmux 2>/dev/null || print 'none')"
  print -r -- "TERM:             ${TERM-?}"
  print -r -- "VTE_VERSION:      ${VTE_VERSION-unset}"
  print -r -- "tty ():           $(command tty 2>/dev/null || print n/a)"
  print -r -- "readable /dev/tty: $([[ -r /dev/tty ]] && print yes || print no)"
  print -r -- "TMUX_PANE:        ${TMUX_PANE:+set}${TMUX_PANE:-unset}"
  print -r -- "Tab (^I) binding: $(bindkey '^I' 2>/dev/null || print n/a)"
  print -r -- "FZF_RTFM_USE_TMUX=${FZF_RTFM_USE_TMUX-unset}"
  print -r -- "FZF_DEFAULT_OPTS length: ${#FZF_DEFAULT_OPTS}"
  print -r -- "fzf merged path opts: ${(j: :)__fzf_rtfm_merged_path_scheme}"
  print -r -- "FZF_RTFM_HIST_DEPTH: ${FZF_RTFM_HIST_DEPTH:-unset (default 4000)}"
  if [[ -n $FZF_DEFAULT_OPTS ]]; then
    print -r -- "FZF_DEFAULT_OPTS (first 500 chars):"
    print -r -- "${FZF_DEFAULT_OPTS:0:500}$([[ ${#FZF_DEFAULT_OPTS} -gt 500 ]] && print '…')"
    [[ "$FZF_DEFAULT_OPTS" == *--filter* ]] && print -u2 -- 'WARNING: FZF_DEFAULT_OPTS contains --filter; can change input behaviour.'
  fi
  print -r -- ""
  print -r -- "=== Manual checks (run in this zsh) ==="
  print -r -- "1) Baseline: fzf opens; type extra letters — they must appear in the bottom prompt line."
  print -r -- "   printf '%s\\n' aa ab bb | fzf --query=a"
  print -r -- "2) Same with ttyctl (matches plugin):"
  print -r -- "   ttyctl -u; printf '%s\\n' aa ab bb | fzf --query=a; ttyctl -f"
  print -r -- "3) If 1 fails only inside an IDE-embedded terminal, try an external xterm/alacritty."
  print -r -- "4) Inside tmux, try:  export FZF_RTFM_USE_TMUX=1  then retry Tab completion."
  print -r -- ""
}

# ---------- Centered floating picker ----------
__fzf_pick() {
  # $1: entries (token<TAB>description)
  # $2: prompt label
  # $3: optional initial fzf query (current token)
  setopt localoptions noxtrace noverbose
  local entries="$1"
  local prompt="$2"
  local query="${3-}"

  local selection fzf_ec=0
  local -a qopts=()
  [[ -n "$query" ]] && qopts=(--query="$query")
  # zsh runs EXIT traps when the enclosing function returns (see zshbuiltins trap).
  local -i __fzf_pick_cleanup_done=0
  __fzf_pick__fin() {
    (( __fzf_pick_cleanup_done )) && return 0
    __fzf_pick_cleanup_done=1
    __fzf_rtfm_zle_parent_tty_restore
    __fzf_tty_refreeze
  }
  trap '__fzf_pick__fin' EXIT INT QUIT

  __fzf_tty_unfreeze
  __fzf_rtfm_zle_parent_tty_prepare
  __fzf_rtfm_drain_tty_input
  selection=$(
    __fzf_rtfm_stty_for_fzf
    printf '%s\n' "$entries" | __fzf_rtfm_fzf_exec \
      --ansi \
      "${__fzf_rtfm_fzf_window_common[@]}" \
      --prompt="$prompt" \
      --delimiter=$'\t' \
      --with-nth=1 \
      --nth=1 \
      --preview "$__fzf_rtfm_preview_script {1} m" \
      --preview-window="$__fzf_rtfm_fzf_preview_window" \
      "${__fzf_rtfm_fzf_binds_preview[@]}" \
      "${qopts[@]}"
    fzf_ec=${pipestatus[-1]}
    __fzf_rtfm_stty_restore
    exit "$fzf_ec"
  ) || fzf_ec=$?

  trap - EXIT INT QUIT
  __fzf_pick__fin

  (( fzf_ec != 0 )) && return 2

  # Only return the left token (everything before the TAB).
  printf '%s\n' "${selection%%$'\t'*}"
}

# ---------- ZLE: Tab (PATH command, then man + files) ----------

__fzf_zle_token_state() {
  typeset -g prefix_rest lastw nwords
  setopt localoptions noshwordsplit extended_glob
  local lb="$LBUFFER"
  local -a words

  # ${(z)} prints a parse dump on unmatched quotes (visible above 90% fzf).
  # Prefer it when it works; fall back to space-split with stderr silenced.
  _fzf_rtfm_try_zsplit() {
    local __s="$1"
    local -a __w
    { __w=("${(z)__s}"); } 2>/dev/null || __w=("${(s: :)__s}")
    __w=("${__w[@]:#}")
    words=("${__w[@]}")
  }

  if [[ "$lb" == *([[:space:]]) ]]; then
    # zsh: use [[:space:]]## — +([[:space:]]) does not strip trailing blanks.
    prefix_rest="${lb%%[[:space:]]##}"
    lastw=""
    _fzf_rtfm_try_zsplit "$prefix_rest"
    nwords=$((${#words} + 1))
  else
    _fzf_rtfm_try_zsplit "$lb"
    nwords=${#words}
    lastw="${words[-1]}"
    if (( nwords >= 2 )); then
      prefix_rest="${words[1]}"
      local i
      for (( i = 2; i < nwords; i++ )); do
        prefix_rest+=" ${words[i]}"
      done
    else
      prefix_rest=""
    fi
  fi
}

# Join a relative pick onto a typed directory prefix in lastw when needed.
# Full/absolute picks and picks already under the prefix are left unchanged.
__fzf_rtfm_resolve_path_pick() {
  setopt localoptions noshwordsplit
  local picked="$1" prefix="${2-$lastw}" base exp
  [[ -n "$picked" ]] || return 1
  if [[ -z "$prefix" || "$picked" == /* ]]; then
    print -r -- "$picked"
    return 0
  fi
  # Only join when the current token is a directory prefix.
  if [[ "$prefix" != */ ]]; then
    exp="$prefix"
    [[ "$exp" == '~'* ]] && exp="${~exp}"
    if [[ ! -d "$exp" ]]; then
      print -r -- "$picked"
      return 0
    fi
  fi
  base="${prefix%/}"
  if [[ -z "$base" || "$picked" == "$base" || "$picked" == "$base"/* || "$picked" == "./$base" || "$picked" == "./$base"/* ]]; then
    print -r -- "$picked"
    return 0
  fi
  # Bare basename (or ./name) under a typed dir prefix → prefix/name.
  print -r -- "${base}/${picked#./}"
}

__fzf_apply_pick() {
  local picked="$1"
  [[ -z "$picked" ]] && return 1
  picked="$(__fzf_rtfm_resolve_path_pick "$picked")"
  if [[ -z "$prefix_rest" ]]; then
    LBUFFER="${picked} "
  else
    LBUFFER="${prefix_rest} ${picked} "
  fi
  zle redisplay
}

__fzf_apply_dir_pick() {
  local picked="$1"
  [[ -z "$picked" ]] && return 1
  picked="$(__fzf_rtfm_resolve_path_pick "$picked")"
  picked="${picked%/}/"
  if [[ -z "$prefix_rest" ]]; then
    LBUFFER="${picked}"
  else
    LBUFFER="${prefix_rest} ${picked}"
  fi
  zle redisplay
}

__fzf_tab_finish_fzf_pick() {
  local rc="$1" picked="$2" apply="$3"
  (( rc == 2 )) && { zle redisplay; return 0; }
  (( rc != 0 )) && return 1
  [[ -z "$picked" ]] && { zle redisplay; return 0; }
  "$apply" "$picked"
}

__fzf_tab_completing_command_name() {
  setopt localoptions noshwordsplit
  local lb="$LBUFFER"
  local -a words
  local trailing=0
  [[ "$lb" == *[[:space:]] ]] && trailing=1
  words=("${(@f)$( __fzf_rtfm_wsplit "$lb" )}")
  local i=1
  while (( i <= ${#words} )) && __fzf_rtfm_is_wrapper "${words[i]}"; do
    (( i++ ))
  done
  local nleft=$(( ${#words} - i + 1 ))
  (( nleft <= 0 )) && return 0
  (( nleft == 1 )) && (( !trailing )) && return 0
  return 1
}

__fzf_path_executable_names() {
  setopt localoptions noshwordsplit
  builtin rehash 2>/dev/null
  local k p
  for k in ${(ko)commands}; do
    p="${commands[$k]}"
    [[ -n "$p" && "$p" == /* ]] || continue
    [[ -f "$p" && -x "$p" ]] || continue
    print -r -- "$k"
  done | command sort -u
}

__fzf_rtfm_cmd_picker_shell_words() {
  setopt localoptions noshwordsplit
  print -rl \
    source export unset alias unalias builtin command eval exec \
    hash rehash cd pushd popd dirs umask trap \
    typeset local integer float readonly noglob \
    autoload zmodload bindkey compdef functions \
    limit logout print printf return break continue true false
}

__fzf_tab_command_names() {
  {
    __fzf_path_executable_names
    __fzf_rtfm_cmd_picker_shell_words
  } | command sort -u
}

__fzf_tab_command_matches() {
  local prefix="$1" n
  while IFS= read -r n; do
    [[ -z "$n" ]] && continue
    if [[ -z "$prefix" || "$n" == "$prefix"* ]]; then
      print -r -- "$n"
    fi
  done
}

__fzf_hist_first_word_counts() {
  local depth="${FZF_RTFM_HIST_DEPTH:-4000}"
  [[ "$depth" =~ ^[0-9]+$ ]] || depth=4000
  fc -ln 1 -1 2>/dev/null | command tail -n "$depth" | command awk '
    {
      w = $1
      sub(/^[ \t\v\f\r]+/, "", w)
      sub(/[ \t\v\f\r]+$/, "", w)
      if (w == "") next
      if (w ~ /^[[:cntrl:]]/) next
      if (w ~ /^[[:punct:]]+$/) next
      if (w ~ /[\001-\037\177]/) next
      if (length(w) > 200) next
      if (index(w, "[") || index(w, "]")) next
      c[w]++
    }
    END {
      for (x in c) printf "%d\t%s\n", c[x], x
    }'
}

__fzf_tab_pick_command() {
  setopt localoptions noshwordsplit
  local q="$1"
  q="$(__fzf_rtfm_normalize_query "$q")"
  typeset -A score
  local cnt w
  while IFS=$'\t' read -r cnt w; do
    [[ "$cnt" =~ ^[0-9]+$ ]] || continue
    [[ -z "$w" ]] && continue
    [[ "$w" == *']'* || "$w" == *'['* ]] && continue
    case "$w" in
      (*[^a-zA-Z0-9_.+:@%-]*) continue ;;
    esac
    score[$w]="$cnt"
  done < <(__fzf_hist_first_word_counts)

  local tmpall
  tmpall=$(mktemp "${TMPDIR:-/tmp}/fzf-tab-cmds.XXXXXX")
  __fzf_tab_command_names | __fzf_tab_command_matches "$q" >"$tmpall"

  local pick fzf_ec=0
  local -i __fzf_pick_cmd_done=0
  __fzf_pick_cmd_fin() {
    ((__fzf_pick_cmd_done)) && return 0
    __fzf_pick_cmd_done=1
    command rm -f "$tmpall"
    __fzf_rtfm_zle_parent_tty_restore
    __fzf_tty_refreeze
  }
  trap '__fzf_pick_cmd_fin' EXIT INT QUIT

  __fzf_tty_unfreeze
  __fzf_rtfm_zle_parent_tty_prepare
  __fzf_rtfm_drain_tty_input
  pick=$(
    __fzf_rtfm_stty_for_fzf
    local sc
    while IFS= read -r cmd; do
      [[ -z "$cmd" ]] && continue
      sc="${score[$cmd]:-0}"
      printf $'%s\t%05d\n' "$cmd" "$sc"
    done <"$tmpall" | command sort -t $'\t' -k2,2nr -k1,1f | __fzf_rtfm_fzf_exec \
      --ansi \
      "${__fzf_rtfm_fzf_window_common[@]}" \
      --prompt='cmd> ' \
      --delimiter=$'\t' \
      --with-nth=1 \
      --nth=1 \
      --tiebreak=begin,length \
      "${__fzf_rtfm_fzf_binds_basic[@]}" \
      --query="$q"
    fzf_ec=${pipestatus[-1]}
    __fzf_rtfm_stty_restore
    exit "$fzf_ec"
  ) || fzf_ec=$?

  trap - EXIT INT QUIT
  __fzf_pick_cmd_fin
  (( fzf_ec != 0 )) && return 2
  [[ -z "$pick" ]] && return 2
  print -r -- "${pick%%$'\t'*}"
  return 0
}

__fzf_tab_try_command() {
  __fzf_tab_completing_command_name || return 1
  local q="$lastw"
  local -a matches
  matches=(${(f)"$(__fzf_tab_command_names | __fzf_tab_command_matches "$q")"})
  if [[ -n "$q" ]] && (( ${#matches} == 1 )); then
    __fzf_apply_pick "${matches[1]}"
    return 0
  fi
  local picked rc
  picked="$(__fzf_tab_pick_command "$q")"
  rc=$?
  __fzf_tab_finish_fzf_pick "$rc" "$picked" __fzf_apply_pick || return
}

__fzf_tab_path_token_dir_base() {
  setopt localoptions noshwordsplit extended_glob
  local exp="${1-$lastw}"
  [[ -z "$exp" ]] && exp='.'
  [[ "$exp" == '~'* ]] && exp="${~exp}"
  if [[ -z "$lastw" ]]; then
    dir='.' base=''
  elif [[ "$lastw" == */ || -d "$exp" ]]; then
    dir="$exp" base=''
    [[ -d "$dir" ]] || dir='.'
  elif [[ -n "$exp" ]]; then
    dir="${exp:h}" base="${exp:t}"
    [[ "$dir" == "." && "$exp" != */* && "$exp" != .*/* ]] && dir='.'
  else
    dir='.' base=''
  fi
  [[ -d "$dir" ]] || dir='.'
}

__fzf_rtfm_text_wants_files() {
  print -r -- "$1" | command awk '
    /<file>|<path>|<dir>|filename/ { hit = 1 }
    /(^|[^A-Za-z0-9_])FILE([^A-Za-z0-9_]|$)/ { hit = 1 }
    /(^|[^A-Za-z0-9_])PATH([^A-Za-z0-9_]|$)/ { hit = 1 }
    /(^|[^A-Za-z0-9_])DIR([^A-Za-z0-9_]|$)/ { hit = 1 }
    tolower($0) ~ /usage:/ { usage = 1 }
    /SYNOPSIS/ { usage = 1 }
    usage {
      for (i = 1; i <= NF; i++) {
        w = $i
        gsub(/[][|()<>,.]/, "", w)
        if (w == "" || w ~ /^-/) continue
        if (w ~ /^(OPTION|OPTIONS|SYNOPSIS|usage|Usage)$/) continue
        if (i == 1) { cmd0 = w; continue }
        if (w != cmd0 && w ~ /^[A-Za-z]/) pos = 1
      }
    }
    END { exit !(hit || pos) }
  '
}

# Drop man trailers so footers with quotes never sit in shell variables.
__fzf_rtfm_docs_trim() {
  command awk '
    /^[[:space:]]*(SEE ALSO|AUTHOR|AUTHORS|REPORTING BUGS|COPYRIGHT|COLOPHON|BUGS|EXIT STATUS|EXIT VALUES)([[:space:]]|$)/ { exit }
    { print }
  '
}

__fzf_rtfm_docs_text() {
  local cmd="$1" sub="$2" text=""
  # Prefer man whenever it exists (including docker-ps); trim footers.
  if [[ -n "$sub" ]] && __fzf_man_topic_exists "${cmd}-${sub}"; then
    text="$(__fzf_rtfm_man_text "${cmd}-${sub}")" || text=""
  elif __fzf_man_topic_exists "$cmd"; then
    text="$(__fzf_rtfm_man_text "$cmd")" || text=""
  fi
  if [[ -z "$text" && "$cmd" == docker ]]; then
    if [[ -n "$sub" ]]; then
      text="$(PAGER=cat MANPAGER=cat docker "$sub" --help 2>/dev/null)" || text=""
    else
      text="$(PAGER=cat MANPAGER=cat docker --help 2>/dev/null)" || text=""
    fi
  fi
  if [[ -z "$text" ]]; then
    __fzf_get_help_text "$cmd" 2>/dev/null
    return $?
  fi
  print -r -- "$text" | __fzf_rtfm_docs_trim
}

# True when the command should mix cwd files into the picker. Avoids loading
# the full man page (quote-laden) on every Tab-continue just to decide.
__fzf_rtfm_cmd_wants_files() {
  local cmd="$1" sub="${2-}" entries="${3-}"
  case "$cmd" in
    ls|ll|la|cat|bat|less|more|head|tail|cp|mv|rm|mkdir|rmdir|touch|chmod|chown|\
    chgrp|file|stat|vim|nvim|nano|emacs|code|tar|unzip|gzip|gunzip|diff|patch|\
    grep|rg|find|fd|hexdump|xxd|source|.)
      return 0
      ;;
    docker)
      case "$sub" in
        run|build|cp|create|export|import|load|save|start) return 0 ;;
        *) return 1 ;;
      esac
      ;;
  esac
  if [[ -n "$entries" ]] && print -r -- "$entries" | __fzf_rtfm_text_wants_files; then
    return 0
  fi
  # SYNOPSIS-only man peek (never the full page / EXIT STATUS / SEE ALSO).
  local topic="$cmd" syn
  [[ -n "$sub" ]] && __fzf_man_topic_exists "${cmd}-${sub}" && topic="${cmd}-${sub}"
  syn="$(__fzf_rtfm_man_text "$topic" 2>/dev/null | command awk '
    NR > 80 { exit }
    /^[[:space:]]*(DESCRIPTION|OPTIONS|EXIT STATUS|EXIT VALUES|SEE ALSO|AUTHOR)([[:space:]]|$)/ { exit }
    { print }
  ')" || syn=""
  [[ -n "$syn" ]] && __fzf_rtfm_text_wants_files "$syn"
}

# Convert token<TAB>desc rows into fzf man_rows, neutralize quotes in descs,
# and drop tokens already present on the command line (no double --author).
__fzf_rtfm_entries_to_man_rows() {
  local entries="$1" cmdline="${2-}"
  {
    if [[ -n "$entries" ]]; then
      print -r -- "$entries"
    elif [[ ! -t 0 ]]; then
      command cat
    else
      return 0
    fi
  } | command awk -F '\t' 'NF {
    desc = $2
    gsub(/[ \t\n\r]+/, " ", desc)
    # Apostrophes in man text (Don'\''t, '\''table'\'') must not reach $SHELL -c.
    gsub(/'\''/, "′", desc)
    print $1 "\tm\t" desc
  }' | __fzf_rtfm_filter_used_line_tokens "$cmdline"
}

# Remove picker rows whose token forms are already on the line.
__fzf_rtfm_filter_used_line_tokens() {
  setopt localoptions noshwordsplit
  local cmdline="${1-}"
  local usedfile w form
  usedfile=$(mktemp "${TMPDIR:-/tmp}/fzf-rtfm-used.XXXXXX") || {
    cat
    return 0
  }
  {
    local -a words
    words=("${(@f)$( __fzf_rtfm_wsplit "$cmdline" )}")
    for w in "${words[@]}"; do
      [[ -n "$w" ]] || continue
      print -r -- "$w"
      form="${w%%\=*}"
      [[ "$form" != "$w" && -n "$form" ]] && print -r -- "$form"
      if [[ "$w" == */* && "$w" != -* ]]; then
        print -r -- "${w:t}"
      fi
    done
  } >"$usedfile"
  command awk -F '\t' '
    NR == FNR { if ($0 != "") u[$0] = 1; next }
    {
      tok = $1
      n = split(tok, forms, /,[ \t]+|[ \t]+/)
      drop = 0
      for (i = 1; i <= n; i++) {
        f = forms[i]
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", f)
        if (f == "") continue
        base = f
        sub(/=.*/, "", base)
        if (u[f] || (base != "" && u[base])) { drop = 1; break }
      }
      if (!drop) print
    }
  ' "$usedfile" -
  local ec=$?
  command rm -f "$usedfile"
  return $ec
}

__fzf_last_word_is_pathlike() {
  local w="$1"
  [[ -n "$w" ]] || return 1
  [[ "$w" == /* || "$w" == ./ || "$w" == ./* || "$w" == ../ || "$w" == ../* || "$w" == '~'* || "$w" == */* ]]
}

# Path listings are always one level deep.
__fzf_rtfm_list_depth() {
  print -r -- 1
}

# True when the current token is already a directory path (src/, /, ~/…).
__fzf_rtfm_is_dir_prefix() {
  setopt localoptions noshwordsplit
  local w="$lastw" exp
  [[ -n "$w" ]] || return 1
  # Explicit forms first — do not rely on glob `*/` alone for root `/`.
  case "$w" in
    / | */ | ./ | ../) return 0 ;;
  esac
  exp="$w"
  [[ "$exp" == '~'* ]] && exp="${~exp}"
  [[ -d "$exp" ]]
}

# True when the token is path-shaped: hide man options/args and show paths only.
__fzf_rtfm_path_only() {
  setopt localoptions noshwordsplit
  [[ -n "$lastw" ]] || return 1
  __fzf_rtfm_is_dir_prefix && return 0
  __fzf_last_word_is_pathlike "$lastw"
}

# True if $1 has entries that the picker would show (mode $2, hidden $3).
__fzf_rtfm_dir_has_entries() {
  setopt localoptions noshwordsplit
  local d="$1" mode="${2:-all}" hidden="${3:-1}" first
  [[ -d "$d" ]] || return 1
  if [[ "$d" == / ]]; then
    if [[ "$hidden" == 1 ]]; then
      first="$(command find / -mindepth 1 -maxdepth 1 \
        \( -path /proc -o -path /sys -o -path /dev -o -path /run \) -prune -o \
        \( -type d -o -type l \) -print 2>/dev/null | command head -n 1)"
    else
      first="$(command find / -mindepth 1 -maxdepth 1 \
        \( -path /proc -o -path /sys -o -path /dev -o -path /run -o -name '.*' \) -prune -o \
        \( -type d -o -type l \) -print 2>/dev/null | command head -n 1)"
    fi
  elif [[ "$mode" == dirs ]]; then
    if [[ "$hidden" == 1 ]]; then
      first="$(command find "$d" -mindepth 1 -maxdepth 1 \( -type d -o -type l \) 2>/dev/null | command head -n 1)"
    else
      first="$(command find "$d" -mindepth 1 -maxdepth 1 \
        \( -name '.*' -prune -o \( -type d -o -type l \) -print \) 2>/dev/null | command head -n 1)"
    fi
    [[ -n "$first" && -d "$first" ]] || return 1
    return 0
  elif [[ "$hidden" == 1 ]]; then
    first="$(command find "$d" -mindepth 1 -maxdepth 1 \( -type f -o -type d -o -type l \) 2>/dev/null | command head -n 1)"
  else
    first="$(command find "$d" -mindepth 1 -maxdepth 1 \
      \( -name '.*' -prune -o \( -type f -o -type d -o -type l \) -print \) 2>/dev/null | command head -n 1)"
  fi
  [[ -n "$first" ]]
}

# File row: display<TAB>f<TAB>fullpath. After zoom, display is the child name only.
__fzf_rtfm_emit_file_row() {
  setopt localoptions noshwordsplit
  local full="$1" dir="${2:-.}" keep="${3:-0}" display
  [[ -n "$full" ]] || return 0
  if [[ "$dir" == . || "$dir" == ./ ]]; then
    display="${full#./}"
  else
    display="${full##*/}"
    [[ -n "$display" ]] || display="$full"
  fi
  if [[ "$keep" == 1 ]]; then
    [[ "$full" == ./* || "$full" == /* ]] || full="./$full"
    if [[ "$dir" == . || "$dir" == ./ ]]; then
      display="$full"
    fi
  fi
  print -r -- "${display}"$'\tf\t'"${full}"
}

# File row → path to insert/zoom; man row → option token.
__fzf_rtfm_row_apply_token() {
  setopt localoptions noshwordsplit
  local row="$1" display kind extra
  [[ -n "$row" ]] || return 1
  display="${row%%$'\t'*}"
  extra="${row#*$'\t'}"
  kind="${extra%%$'\t'*}"
  extra="${extra#*$'\t'}"
  extra="${extra%%$'\t'*}"
  if [[ "$kind" == f && -n "$extra" ]]; then
    print -r -- "$extra"
  else
    print -r -- "$display"
  fi
}

__fzf_rtfm_zoom_prompt() {
  setopt localoptions noshwordsplit
  local d="${1%/}"
  if [[ "$d" == / || -z "$d" ]]; then
    print -r -- '/ > '
  else
    print -r -- "${d:t}/ > "
  fi
}

__fzf_tab_immediate_file_rows() {
  setopt localoptions noshwordsplit
  local dir="$1" mode="${2:-all}" depth="${3:-1}" hidden="${4:-1}" p name
  [[ -d "$dir" ]] || return 0
  [[ "$depth" == <-> ]] || depth=1
  local keep_dotslash=0
  [[ "$lastw" == ./ || "$lastw" == ./* ]] && keep_dotslash=1
  # Offer / from cwd so cat/cd Tab can enter the root without typing it.
  if [[ "$dir" == . || "$dir" == ./ ]]; then
    print -r -- "/"$'\tf\t'"/"
  fi
  {
    if [[ "$dir" == / ]]; then
      # Root: directories only; skip virtual filesystems.
      if [[ "$hidden" == 1 ]]; then
        command find / -mindepth 1 -maxdepth "$depth" \
          \( -path /proc -o -path /sys -o -path /dev -o -path /run \) -prune -o \
          \( -type d -o -type l \) -print
      else
        command find / -mindepth 1 -maxdepth "$depth" \
          \( -path /proc -o -path /sys -o -path /dev -o -path /run -o -name '.*' \) -prune -o \
          \( -type d -o -type l \) -print
      fi
    elif [[ "$hidden" == 1 ]]; then
      if [[ "$mode" == dirs ]]; then
        command find "$dir" -mindepth 1 -maxdepth "$depth" \( -type d -o -type l \)
      else
        command find "$dir" -mindepth 1 -maxdepth "$depth" \( -type f -o -type d -o -type l \)
      fi
    else
      if [[ "$mode" == dirs ]]; then
        command find "$dir" -mindepth 1 -maxdepth "$depth" \
          \( -name '.*' -prune -o \( -type d -o -type l \) -print \)
      else
        command find "$dir" -mindepth 1 -maxdepth "$depth" \
          \( -name '.*' -prune -o \( -type f -o -type d -o -type l \) -print \)
      fi
    fi
  } 2>/dev/null | command sort | while IFS= read -r p; do
      [[ -z "$p" ]] && continue
      if [[ "$mode" == dirs || "$dir" == / ]] && [[ ! -d "$p" ]]; then
        continue
      fi
      name="$p"
      if [[ "$dir" == . || "$dir" == ./ ]]; then
        name="${p#./}"
      fi
      # Never offer . / .. / path/.. as picks.
      case "$name" in
        . | .. | */. | */..) continue ;;
      esac
      __fzf_rtfm_emit_file_row "$name" "$dir" "$keep_dotslash"
    done
}

__fzf_tab_try_path_firstword() {
  setopt localoptions noshwordsplit
  [[ -n "$lastw" ]] || return 1
  __fzf_last_word_is_pathlike "$lastw" || return 1
  local dir base q file_rows list_mode=all
  dir='.' base=''
  __fzf_tab_path_token_dir_base
  __fzf_rtfm_is_dir_prefix && list_mode=dirs
  file_rows="$(__fzf_tab_immediate_file_rows "$dir" "$list_mode" 1 1)"
  [[ -n "$file_rows" ]] || { zle redisplay; return 0; }
  q="$base"
  __fzf_rtfm_browse_apply "" "$file_rows" 'path> ' "$q" all || return
}

__fzf_pick_mixed() {
  setopt localoptions noxtrace noverbose
  local entries="$1" prompt="$2" query="${3-}"
  local with_expect="${4-}"
  local zoom_mode="${5:-all}"
  local list_dir="${6:-.}"
  local list_depth="${7:-1}"
  local man_rows="${8-}"
  local list_mode="${9:-$zoom_mode}"
  local selection fzf_ec=0 ps state lister transformer toggler manfile
  local entries_file filterfile searchstate searcher search_enter search_next search_prev search_esc promptfile
  local preview_out focus_script
  local -a qopts=() expect_opts=() bind_opts=() scheme_opts=() preview_opts=()
  local keep_dotslash=0
  [[ "$lastw" == ./ || "$lastw" == ./* ]] && keep_dotslash=1
  [[ -n "$query" ]] && qopts=(--query="$query")
  [[ -d "$list_dir" ]] || list_dir='.'
  [[ "$list_depth" == <-> ]] || list_depth=1
  [[ "$list_mode" == dirs || "$list_mode" == all ]] || list_mode="$zoom_mode"
  [[ "$zoom_mode" == dirs || "$zoom_mode" == all ]] || zoom_mode=all
  list_depth=1
  scheme_opts=("${__fzf_rtfm_merged_path_scheme[@]}")
  __fzf_rtfm_ensure_preview_script || return 1
  ps="$__fzf_rtfm_preview_script"
  state=
  lister=
  transformer=
  toggler=
  manfile=
  entries_file=
  filterfile=
  searchstate=
  searcher=
  search_enter=
  search_next=
  search_prev=
  search_esc=
  promptfile=
  preview_out=
  focus_script=

  if [[ -n "$with_expect" ]]; then
    state=$(mktemp "${TMPDIR:-/tmp}/fzf-rtfm-nav.XXXXXX")
    lister=$(mktemp "${TMPDIR:-/tmp}/fzf-rtfm-ls.XXXXXX")
    transformer=$(mktemp "${TMPDIR:-/tmp}/fzf-rtfm-tr.XXXXXX")
    toggler=$(mktemp "${TMPDIR:-/tmp}/fzf-rtfm-tg.XXXXXX")
    manfile=$(mktemp "${TMPDIR:-/tmp}/fzf-rtfm-man.XXXXXX")
    {
      print -r -- "$list_dir"
      print -r -- 1
      print -r -- "$list_depth"
      if [[ -n "$man_rows" ]]; then
        print -r -- 1
      else
        print -r -- 0
      fi
      print -r -- "$list_mode"
    } >"$state"
    if [[ -n "$man_rows" ]]; then
      print -r -- "$man_rows" >"$manfile"
    else
      : >"$manfile"
    fi
    __fzf_rtfm_write_lister "$lister" "$state" "$manfile" "$keep_dotslash"
    __fzf_rtfm_write_transformer "$transformer" "$state" "$lister" "$zoom_mode"
    __fzf_rtfm_write_toggler "$toggler" "$state" "$lister"
    command chmod +x "$lister" "$transformer" "$toggler"
    # Preview via a fixed file path only — never put man/desc text into
    # $SHELL -c through fzf placeholders (quotes in man pages dump above fzf).
    preview_out=$(mktemp "${TMPDIR:-/tmp}/fzf-rtfm-pout.XXXXXX")
    focus_script=$(mktemp "${TMPDIR:-/tmp}/fzf-rtfm-pfocus.XXXXXX")
    print -r -- "$entries" | command awk -F '\t' 'NF {
      if ($2 == "f") { if ($3 != "") print $3; else print $1; exit }
      print $3; exit
    }' >"$preview_out"
    {
      print -r '#!/bin/sh'
      print -r "manfile='$manfile'"
      print -r "preview_out='$preview_out'"
      print -r "statefile='$state'"
      print -r 'tok=$1'
      print -r 'dir=$(sed -n "1p" "$statefile" 2>/dev/null)'
      print -r '[ -n "$dir" ] || dir=.'
      print -r 'path=$tok'
      print -r 'if [ "$dir" != . ] && [ "$dir" != ./ ] && [ ! -e "$tok" ] && [ ! -L "$tok" ]; then'
      print -r '  case "$dir" in'
      print -r '    /) cand="/$tok" ;;'
      print -r '    *) cand="$dir/${tok#./}" ;;'
      print -r '  esac'
      print -r '  if [ -e "$cand" ] || [ -L "$cand" ]; then path=$cand; fi'
      print -r 'fi'
      print -r 'if [ -e "$path" ] || [ -L "$path" ]; then'
      print -r '  ls -ld -- "$path" > "$preview_out" 2>/dev/null'
      print -r '  exit 0'
      print -r 'fi'
      print -r 'awk -F "\t" -v t="$tok" '\''$1==t { print $3; exit }'\'' "$manfile" > "$preview_out" 2>/dev/null'
    } >"$focus_script"
    command chmod +x "$focus_script"
    # Preview is ONLY `cat` of a fixed path — no man text in $SHELL -c.
    # Focus updates write the short desc into that file, then refresh.
    preview_opts=(
      --preview="cat -- '$preview_out'"
      --preview-window="$__fzf_rtfm_fzf_preview_window"
      --bind "focus:execute-silent($focus_script {1})+refresh-preview"
    )
    # Enter via transform when man_rows present; otherwise --expect=enter.
    expect_opts=(--expect=tab,enter)
    bind_opts=(
      "${__fzf_rtfm_fzf_binds_preview_nav[@]}"
      --bind "tab:transform:$transformer {1}"
      --bind "alt-.:transform:$toggler"
    )

    # Ctrl-f regex search among man options/arguments only.
    # Type the pattern in fzf's own input line (prompt becomes regex> ) so it is visible.
    # Enter filters the list to all matches (browse with arrows / n / N|p); does not accept.
    if [[ -n "$man_rows" ]]; then
      # Enter is handled by search_enter (filter or accept); keep Tab as --expect only.
      expect_opts=(--expect=tab)
      entries_file=$(mktemp "${TMPDIR:-/tmp}/fzf-rtfm-ent.XXXXXX")
      filterfile=$(mktemp "${TMPDIR:-/tmp}/fzf-rtfm-fl.XXXXXX")
      searchstate=$(mktemp "${TMPDIR:-/tmp}/fzf-rtfm-sr.XXXXXX")
      searcher=$(mktemp "${TMPDIR:-/tmp}/fzf-rtfm-sf.XXXXXX")
      search_enter=$(mktemp "${TMPDIR:-/tmp}/fzf-rtfm-se2.XXXXXX")
      search_next=$(mktemp "${TMPDIR:-/tmp}/fzf-rtfm-sn.XXXXXX")
      search_prev=$(mktemp "${TMPDIR:-/tmp}/fzf-rtfm-sp.XXXXXX")
      search_esc=$(mktemp "${TMPDIR:-/tmp}/fzf-rtfm-se.XXXXXX")
      promptfile=$(mktemp "${TMPDIR:-/tmp}/fzf-rtfm-pr.XXXXXX")
      : >"$searchstate"
      : >"$filterfile"
      printf '%s\n' "$entries" >"$entries_file"
      printf '%s' "$prompt" >"$promptfile"
      __fzf_rtfm_write_transformer "$transformer" "$state" "$lister" "$zoom_mode" \
        "$searchstate" "$filterfile" "$promptfile"
      __fzf_rtfm_write_toggler "$toggler" "$state" "$lister" "$searchstate" "$filterfile"
      command chmod +x "$transformer" "$toggler"
      # Ctrl-f: enter compose mode — type regex in the visible fzf input line.
      {
        print -r '#!/bin/sh'
        print -r "searchstate='$searchstate'"
        print -r "statefile='$state'"
        print -r 'show_man=$(sed -n "4p" "$statefile")'
        print -r '[ "$show_man" = 1 ] || { printf "ignore\n"; exit 0; }'
        print -r 'printf "%s\n" __COMPOSE__ > "$searchstate"'
        print -r 'printf "change-prompt(regex> )+clear-query+disable-search+unbind(tab)+unbind(n)+unbind(N)+unbind(p)+change-header(type regex · Enter filter · Esc cancel)\n"'
      } >"$searcher"
      # Enter: filter list to all regex matches while composing; otherwise accept.
      {
        print -r '#!/bin/sh'
        print -r "entries_file='$entries_file'"
        print -r "filterfile='$filterfile'"
        print -r "searchstate='$searchstate'"
        print -r "promptfile='$promptfile'"
        print -r 'mode=$(sed -n "1p" "$searchstate")'
        print -r 'if [ "$mode" != "__COMPOSE__" ]; then'
        print -r '  printf "accept\n"'
        print -r '  exit 0'
        print -r 'fi'
        print -r 'pat=$FZF_QUERY'
        print -r 'if [ -z "$pat" ]; then'
        print -r '  printf "change-header(type regex · Enter filter · Esc cancel)\n"'
        print -r '  exit 0'
        print -r 'fi'
        print -r 'if printf "%s\n" x | grep -E -e "$pat" >/dev/null 2>&1; then'
        print -r '  :'
        print -r 'else'
        print -r '  ec=$?'
        print -r '  if [ "$ec" -eq 2 ]; then'
        print -r '    printf "change-header(invalid regex · edit and Enter · Esc cancel)\n"'
        print -r '    exit 0'
        print -r '  fi'
        print -r 'fi'
        print -r ': > "$filterfile"'
        print -r 'nmatch=0'
        print -r 'while IFS= read -r line || [ -n "$line" ]; do'
        print -r '  kind=$(printf %s "$line" | cut -f2)'
        print -r '  [ "$kind" = m ] || continue'
        print -r '  tok=$(printf %s "$line" | cut -f1)'
        print -r '  desc=$(printf %s "$line" | cut -f3-)'
        print -r '  if printf "%s\n%s\n" "$tok" "$desc" | grep -E -e "$pat" >/dev/null 2>&1; then'
        print -r '    printf "%s\n" "$line" >> "$filterfile"'
        print -r '    nmatch=$((nmatch + 1))'
        print -r '  fi'
        print -r 'done < "$entries_file"'
        print -r 'if [ "$nmatch" -eq 0 ]; then'
        print -r '  : > "$filterfile"'
        print -r '  printf "change-header(no matches · edit regex · Enter filter · Esc cancel)\n"'
        print -r '  exit 0'
        print -r 'fi'
        print -r 'printf "%s\n" "$pat" > "$searchstate"'
        print -r 'hdr_pat=$(printf %s "$pat" | tr "()\n\t" "[]  ")'
        print -r 'printf "transform-prompt(cat %s)+enable-search+clear-query+reload(cat %s)+first+rebind(tab)+rebind(n)+rebind(N)+rebind(p)+change-header(search: %s  %s matches · n/N move · type to refine · Esc clear)\n" "$promptfile" "$filterfile" "$hdr_pat" "$nmatch"'
      } >"$search_enter"
      {
        print -r '#!/bin/sh'
        print -r "searchstate='$searchstate'"
        print -r 'pat=$(sed -n "1p" "$searchstate")'
        print -r '[ -n "$pat" ] || { printf "ignore\n"; exit 0; }'
        print -r '[ "$pat" = "__COMPOSE__" ] && { printf "ignore\n"; exit 0; }'
        print -r 'printf "down\n"'
      } >"$search_next"
      {
        print -r '#!/bin/sh'
        print -r "searchstate='$searchstate'"
        print -r 'pat=$(sed -n "1p" "$searchstate")'
        print -r '[ -n "$pat" ] || { printf "ignore\n"; exit 0; }'
        print -r '[ "$pat" = "__COMPOSE__" ] && { printf "ignore\n"; exit 0; }'
        print -r 'printf "up\n"'
      } >"$search_prev"
      {
        print -r '#!/bin/sh'
        print -r "searchstate='$searchstate'"
        print -r "promptfile='$promptfile'"
        print -r "entries_file='$entries_file'"
        print -r "filterfile='$filterfile'"
        print -r "lister='$lister'"
        print -r 'pat=$(sed -n "1p" "$searchstate")'
        print -r 'if [ "$pat" = "__COMPOSE__" ]; then'
        print -r '  : > "$searchstate"'
        print -r '  printf "transform-prompt(cat %s)+enable-search+clear-query+rebind(tab)+change-header()\n" "$promptfile"'
        print -r 'elif [ -n "$pat" ]; then'
        print -r '  : > "$searchstate"'
        print -r '  : > "$filterfile"'
        print -r '  printf "reload(%s)+clear-query+unbind(n)+unbind(N)+unbind(p)+change-header()\n" "$lister"'
        print -r 'else'
        print -r '  printf "abort\n"'
        print -r 'fi'
      } >"$search_esc"
      command chmod +x "$searcher" "$search_enter" "$search_next" "$search_prev" "$search_esc"
      bind_opts+=(
        --bind "start:unbind(n,N,p)"
        --bind "ctrl-f:transform:$searcher"
        --bind "enter:transform:$search_enter"
        --bind "n:transform:$search_next"
        --bind "N:transform:$search_prev"
        --bind "p:transform:$search_prev"
        --bind "esc:transform:$search_esc"
      )
    fi
  else
    bind_opts=("${__fzf_rtfm_fzf_binds_preview[@]}")
    preview_opts=(
      --preview="cat -- /dev/null"
      --preview-window="$__fzf_rtfm_fzf_preview_window"
    )
  fi

  local -i __fzf_mixed_done=0
  __fzf_mixed_fin() {
    ((__fzf_mixed_done)) && return 0
    __fzf_mixed_done=1
    # Do not remove cached preview script ($ps / __fzf_rtfm_preview_script).
    command rm -f "$state" "$lister" "$transformer" "$toggler" "$manfile" \
      "$entries_file" "$filterfile" "$searchstate" "$searcher" "$search_enter" \
      "$search_next" "$search_prev" "$search_esc" "$promptfile" \
      "$preview_out" "$focus_script"
    __fzf_rtfm_zle_parent_tty_restore
    __fzf_tty_refreeze
  }
  trap '__fzf_mixed_fin' EXIT INT QUIT

  __fzf_tty_unfreeze
  __fzf_rtfm_zle_parent_tty_prepare
  __fzf_rtfm_drain_tty_input
  selection=$(
    __fzf_rtfm_stty_for_fzf
    printf '%s\n' "$entries" | __fzf_rtfm_fzf_exec \
      --ansi \
      "${__fzf_rtfm_fzf_window_common[@]}" \
      --prompt="$prompt" \
      --delimiter=$'\t' \
      --with-nth=1 \
      --nth=1 \
      --tiebreak=begin,length \
      "${preview_opts[@]}" \
      "${scheme_opts[@]}" \
      "${bind_opts[@]}" \
      "${expect_opts[@]}" \
      "${qopts[@]}"
    fzf_ec=${pipestatus[-1]}
    __fzf_rtfm_stty_restore
    exit "$fzf_ec"
  ) || fzf_ec=$?

  trap - EXIT INT QUIT
  __fzf_mixed_fin
  (( fzf_ec != 0 )) && return 2
  [[ -z "$selection" ]] && return 2
  print -r -- "$selection"
  return 0
}

__fzf_rtfm_first_option_form() {
  # "-A, --all" or "-A --all" → "-A". Subcommands and single options are unchanged.
  setopt localoptions noshwordsplit
  local tok="$1"
  [[ "$tok" == -* ]] || { print -r -- "$tok"; return 0 }
  local first rest
  if [[ "$tok" == *,* ]]; then
    first="${tok%%,*}"
  else
    first="${tok%% *}"
    rest="${tok#"$first"}"
    rest="${rest#"${rest%%[![:space:]]*}"}"
    if [[ "$tok" != *' '* || "$rest" != -* ]]; then
      print -r -- "$tok"
      return 0
    fi
  fi
  first="${first#"${first%%[![:space:]]*}"}"
  first="${first%"${first##*[![:space:]]}"}"
  print -r -- "$first"
}

__fzf_apply_mixed_pick() {
  local row="$1" kind tok
  [[ -z "$row" ]] && return 1
  kind="${row#*$'\t'}"
  kind="${kind%%$'\t'*}"
  tok="$(__fzf_rtfm_row_apply_token "$row")"
  [[ -z "$tok" ]] && return 1
  if [[ "$kind" == f && -d "$tok" ]]; then
    __fzf_apply_dir_pick "$tok"
  else
    [[ "$kind" == m ]] && tok="$(__fzf_rtfm_first_option_form "$tok")"
    __fzf_apply_pick "$tok"
  fi
}

# ZLE-only (do not call from $(...)): listings are always depth 1. Tab on a
# non-empty dir shows that directory’s immediate children; Tab on a file, option,
# or empty dir inserts it and reopens the picker for the next token. Enter inserts
# and returns to the shell. Alt-. toggles hidden names. Esc leaves the line as-is.
__fzf_rtfm_browse_apply() {
  # xtrace prints `_entries=$'…man…'` into the 90% gap above fzf on Tab-continue.
  setopt localoptions noshwordsplit noxtrace noverbose
  local man_rows="$1" file_rows="$2" prompt="$3" q="$4" mode="$5"
  local orig_man_rows="$man_rows"
  local use_man=1
  local mixed raw rc key row kind tok
  local show_prompt="$prompt"
  local dir='.' base='' list_dir list_depth list_mode
  __fzf_tab_path_token_dir_base
  list_dir="$dir"
  list_depth=1
  list_mode="$mode"
  if __fzf_rtfm_is_dir_prefix; then
    list_mode=dirs
  fi
  # Any path token: never mix man options/arguments into the picker.
  if __fzf_rtfm_path_only; then
    use_man=0
    man_rows=""
  fi

  while true; do
    if (( use_man )) && [[ -n "$man_rows" ]]; then
      mixed="$(printf '%s\n%s\n' "$man_rows" "$file_rows" | command awk 'NF')"
    else
      mixed="$(printf '%s\n' "$file_rows" | command awk 'NF')"
    fi
    if [[ -z "$mixed" ]]; then
      zle -M 'RTFM: nothing to complete'
      zle redisplay
      return 0
    fi

    raw="$(__fzf_pick_mixed "$mixed" "$show_prompt" "$q" expect "$mode" "$list_dir" "$list_depth" "$man_rows" "$list_mode")"
    rc=$?
    if (( rc == 2 )); then
      zle redisplay
      return 0
    fi
    (( rc != 0 )) && return 1

    key="${raw%%$'\n'*}"
    if [[ "$raw" == *$'\n'* ]]; then
      row="${raw#*$'\n'}"
      row="${row%$'\n'}"
    else
      row="$raw"
      key=""
    fi
    [[ -z "$row" ]] && { zle redisplay; return 0; }

    kind="${row#*$'\t'}"
    kind="${kind%%$'\t'*}"
    tok="$(__fzf_rtfm_row_apply_token "$row")"

    if [[ "$kind" == f && -n "$tok" && -d "$tok" ]]; then
      if [[ "$key" == tab ]] && __fzf_rtfm_dir_has_entries "$tok" "$mode" 1; then
        lastw="${tok%/}/"
        list_dir="$tok"
        list_depth=1
        list_mode="$mode"
        file_rows="$(__fzf_tab_immediate_file_rows "$tok" "$list_mode" 1 1)"
        if [[ -n "$file_rows" ]]; then
          use_man=0
          man_rows=""
          q=""
          show_prompt="$(__fzf_rtfm_zoom_prompt "$tok")"
          continue
        fi
      fi
    fi

    # Enter (or plain accept): insert and return to the shell.
    if [[ "$key" != tab ]]; then
      if [[ "$kind" == f && -n "$tok" && -d "$tok" ]] && ! __fzf_rtfm_dir_has_entries "$tok" "$mode" 1; then
        __fzf_apply_pick "${tok%/}/"
      else
        __fzf_apply_mixed_pick "$row"
      fi
      return 0
    fi

    # Tab: insert the pick, then reopen the picker for the next token.
    if [[ "$kind" == f && -n "$tok" && -d "$tok" ]] && ! __fzf_rtfm_dir_has_entries "$tok" "$mode" 1; then
      __fzf_apply_pick "${tok%/}/"
    else
      __fzf_apply_mixed_pick "$row"
    fi
    __fzf_zle_token_state
    q=""
    list_dir='.'
    list_depth=1
    list_mode="$mode"
    # Rebuild options for the new line (e.g. docker → docker ps --all, not root again).
    man_rows=""
    use_man=0
    file_rows=""
    if ! __fzf_rtfm_path_only; then
      local _parsed _cmd _sub
      _parsed="$(__fzf_get_cmd_and_sub)" || _parsed=""
      _cmd="${_parsed%%$'\t'*}"
      _sub="${_parsed#*$'\t'}"
      if [[ -n "$_cmd" ]] && ! __fzf_rtfm_is_wrapper "$_cmd"; then
        if [[ "$_cmd" == cd || "$_cmd" == pushd ]]; then
          man_rows=$'-L\tm\tfollow symbolic links\n-P\tm\tuse the physical directory structure'
          use_man=1
          list_mode=dirs
        elif man_rows="$(__fzf_build_entries_cached "$_cmd" "$_sub" "${LBUFFER}${RBUFFER}" 2>/dev/null | __fzf_rtfm_entries_to_man_rows "" "${LBUFFER}${RBUFFER}")"; then
          [[ -n "$man_rows" ]] && use_man=1
        fi
        show_prompt="${_cmd}${_sub:+ $_sub} > "
      else
        show_prompt="$prompt"
      fi
    else
      show_prompt="$prompt"
    fi
    # Already-chosen path args: drop them from the next file list.
    if [[ "$_cmd" == cd || "$_cmd" == pushd ]]; then
      man_rows="$(print -r -- "$man_rows" | __fzf_rtfm_filter_used_line_tokens "${LBUFFER}${RBUFFER}")"
    fi
    orig_man_rows="$man_rows"
    if __fzf_rtfm_is_dir_prefix; then
      list_mode=dirs
    fi
    __fzf_tab_path_token_dir_base
    list_dir="$dir"
    if [[ "$list_mode" == dirs ]] || __fzf_rtfm_path_only || [[ -n "$man_rows" ]]; then
      # Paths when path-only, dir mode, or when usage may want files — refresh cwd listing.
      if __fzf_rtfm_path_only || [[ "$list_mode" == dirs ]]; then
        file_rows="$(__fzf_tab_immediate_file_rows "$list_dir" "$list_mode" 1 1)"
      else
        if __fzf_rtfm_cmd_wants_files "${_cmd-}" "${_sub-}"; then
          file_rows="$(__fzf_tab_immediate_file_rows "$list_dir" all 1 1)"
        fi
      fi
      [[ -n "$file_rows" ]] && file_rows="$(print -r -- "$file_rows" | __fzf_rtfm_filter_used_line_tokens "${LBUFFER}${RBUFFER}")"
    fi
    continue
  done
}

__fzf_tab_try_rtfm() {
  setopt localoptions noshwordsplit noxtrace noverbose
  __fzf_tab_completing_command_name && return 1

  local parsed cmd sub entries dir base q
  parsed="$(__fzf_get_cmd_and_sub)" || return 1
  cmd="${parsed%%$'\t'*}"
  sub="${parsed#*$'\t'}"
  [[ -z "$cmd" ]] && return 1
  __fzf_rtfm_is_wrapper "$cmd" && return 1

  # If the current token is still the subcommand word (no trailing space):
  # keep sub only when it is a finished sub (its page differs from root).
  # Incomplete prefixes (`docker p`, `git sta`) stay as the fzf query.
  local sub_complete=0
  if __fzf_rtfm_sub_token_complete "$cmd" "$sub" "$lastw" "${LBUFFER}${RBUFFER}"; then
    sub_complete=1
  elif [[ -n "$sub" && "$lastw" == "$sub" && "$lastw" != -* ]]; then
    sub=""
  fi

  entries=""
  if [[ "$cmd" != cd && "$cmd" != pushd ]]; then
    if entries="$(__fzf_build_entries_cached "$cmd" "$sub" "${LBUFFER}${RBUFFER}" 2>/dev/null)"; then
      :
    else
      entries=""
    fi
  fi

  local man_rows=""
  local file_rows=""

  local path_only=0 dir_only=0
  __fzf_rtfm_path_only && path_only=1
  __fzf_rtfm_is_dir_prefix && dir_only=1

  local cmdline="${LBUFFER}${RBUFFER}"
  if [[ "$cmd" == cd || "$cmd" == pushd ]]; then
    # Do not use man cd (often Tcl) or man -k ^cd- (cd-paranoia as fake subcommands).
    # Path token: directories only (no -L/-P options).
    if (( !path_only )); then
      man_rows=$'-L\tm\tfollow symbolic links\n-P\tm\tuse the physical directory structure'
      man_rows="$(print -r -- "$man_rows" | __fzf_rtfm_filter_used_line_tokens "$cmdline")"
    fi
    if [[ "$lastw" != -* ]]; then
      dir='.' base=''
      __fzf_tab_path_token_dir_base
      file_rows="$(__fzf_tab_immediate_file_rows "$dir" dirs 1 1)"
    fi
  else
    if (( !path_only )) && [[ -n "$entries" ]]; then
      man_rows="$(__fzf_rtfm_entries_to_man_rows "$entries" "$cmdline")"
    else
      man_rows=""
    fi
    if [[ "$lastw" != -* ]]; then
      if (( path_only )) || __fzf_rtfm_cmd_wants_files "$cmd" "$sub" "$entries"; then
        local list_mode=all
        dir='.' base=''
        __fzf_tab_path_token_dir_base
        (( dir_only )) && list_mode=dirs
        file_rows="$(__fzf_tab_immediate_file_rows "$dir" "$list_mode" 1 1)"
      fi
    fi
  fi

  # Belt and suspenders: never pass options when the token is a path.
  if (( path_only )); then
    man_rows=""
  fi
  [[ -n "$file_rows" ]] && file_rows="$(print -r -- "$file_rows" | __fzf_rtfm_filter_used_line_tokens "$cmdline")"

  local mixed
  if [[ -n "$man_rows" ]]; then
    mixed="$(printf '%s\n%s\n' "$man_rows" "$file_rows" | command awk 'NF')"
  else
    mixed="$(printf '%s\n' "$file_rows" | command awk 'NF')"
  fi
  [[ -n "$mixed" ]] || { zle redisplay; return 0; }

  q="$lastw"
  if [[ "$lastw" == / || "$lastw" == */* || "$lastw" == */ ]]; then
    q="$base"
  fi
  # Complete sub on the token (`docker ps`, `git status`): show its options
  # unfiltered. Incomplete prefix (`docker p`, `git sta`): keep q=lastw.
  if (( sub_complete )); then
    q=""
  fi

  local mode=all
  [[ "$cmd" == cd || "$cmd" == pushd ]] && mode=dirs
  local show_prompt="$cmd > "
  [[ -n "$sub" && ( -z "$lastw" || sub_complete -eq 1 ) ]] && show_prompt="$cmd $sub > "
  __fzf_rtfm_browse_apply "$man_rows" "$file_rows" "$show_prompt" "$q" "$mode" || return
}

fzf_tab_unified_impl() {
  setopt localoptions noshwordsplit extended_glob noxtrace noverbose
  __fzf_zle_token_state
  if __fzf_tab_completing_command_name && [[ -n "$lastw" ]] && __fzf_last_word_is_pathlike "$lastw"; then
    __fzf_tab_try_path_firstword || zle redisplay
    return 0
  fi
  if __fzf_tab_try_command; then
    # Command inserted as "cmd ": refresh tokens and open options/arguments next.
    __fzf_zle_token_state
    if ! __fzf_tab_completing_command_name; then
      __fzf_tab_try_rtfm || zle redisplay
    else
      zle redisplay
    fi
    return 0
  fi
  if __fzf_tab_try_rtfm; then
    return 0
  fi
  zle redisplay
}

fzf_rtfm_rebind_tab() {
  bindkey '^I' fzf_tab_unified_widget
  bindkey -r '^[m' 2>/dev/null || true
}

zle -N fzf_tab_unified_widget fzf_tab_unified_impl

bindkey '^I' fzf_tab_unified_widget
bindkey -r '^[m' 2>/dev/null || true
