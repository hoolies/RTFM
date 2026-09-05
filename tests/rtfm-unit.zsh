#!/usr/bin/env zsh
# Lightweight unit tests for RTFM helpers (no interactive fzf).
# Run: zsh tests/rtfm-unit.zsh
emulate -L zsh
setopt localoptions
0=${(%):-%x}
ROOT="${0:A:h:h}"

zle() { :; }
bindkey() { :; }
builtin source "$ROOT/fzf-man-opts.zsh"

typeset -i PASS=0 FAIL=0
assert_ok() {
  local name="$1"
  shift
  if eval "$*"; then
    print -r -- "ok  - $name"
    PASS=$((PASS + 1))
  else
    print -r -- "FAIL- $name"
    FAIL=$((FAIL + 1))
  fi
}

# --- token state must strip trailing blanks (avoids "ls  --all") ---
LBUFFER='ls '
__fzf_zle_token_state
assert_ok 'token state strips trailing space from prefix_rest' \
  '[[ "$prefix_rest" == ls && -z "$lastw" ]]'
LBUFFER='ls  '
__fzf_zle_token_state
assert_ok 'token state strips multiple trailing spaces' \
  '[[ "$prefix_rest" == ls ]]'
prefix_rest='ls'
lastw=''
__fzf_apply_pick '--all'
assert_ok 'apply after spaced line uses single separator' \
  '[[ "$LBUFFER" == "ls --all " ]]'

# --- path join ---
lastw='src/'
prefix_rest='cat'
assert_ok 'resolve joins bare name under src/' \
  '[[ "$(__fzf_rtfm_resolve_path_pick foo)" == src/foo ]]'
assert_ok 'resolve keeps full path under prefix' \
  '[[ "$(__fzf_rtfm_resolve_path_pick src/foo)" == src/foo ]]'
assert_ok 'resolve keeps absolute' \
  '[[ "$(__fzf_rtfm_resolve_path_pick /etc/passwd)" == /etc/passwd ]]'
lastw=''
assert_ok 'resolve unchanged without prefix' \
  '[[ "$(__fzf_rtfm_resolve_path_pick foo)" == foo ]]'

# --- sv wrappers ---
assert_ok 'sv status offers services' \
  '__fzf_sv_should_offer_services "sv status"'
assert_ok 'sudo sv status offers services' \
  '__fzf_sv_should_offer_services "sudo sv status"'
assert_ok 'doas sv status offers services' \
  '__fzf_sv_should_offer_services "doas sv status"'
assert_ok 'sv alone does not offer services' \
  '! __fzf_sv_should_offer_services "sv"'
assert_ok 'sv unknown-verb fails' \
  '! __fzf_sv_should_offer_services "sv notaverb"'

# --- dash options: continuation that starts a new option must not drop prior ---
parsed="$(print -r -- '
       -a, --all
              all the things
       -b, --brief
              brief mode
' | __fzf_parse_dash_options_block)"
assert_ok 'parse emits -a or --all' '[[ "$parsed" == *"-a"* || "$parsed" == *"--all"* ]]'
assert_ok 'parse emits -b or --brief' '[[ "$parsed" == *"-b"* || "$parsed" == *"--brief"* ]]'

# procps ps(1) puts EXAMPLES before any dash options; do not abort there.
parsed_ex="$(print -r -- '
EXAMPLES
       ps -e
SIMPLE PROCESS SELECTION
       -A     Select all processes.  Identical to -e.
       -e     Select all processes.  Identical to -A.
       --deselect
              Negate the selection.
NOTES
       leftover should not be parsed
       --bogus
' | __fzf_parse_dash_options_block)"
assert_ok 'parse skips leading EXAMPLES then reads options' \
  '[[ "$parsed_ex" == *"-A"* && "$parsed_ex" == *"-e"* && "$parsed_ex" == *"--deselect"* ]]'
assert_ok 'parse still stops at NOTES after options' \
  '[[ "$parsed_ex" != *"--bogus"* ]]'

# --- help Commands: / Available Commands: / subcommands: (pip, cobra, clap) ---
pip_help='Usage:
  pip <command> [options]

Commands:
  install                     Install packages.
  lock                        Generate a lock file.
  check                       Verify installed packages have compatible
dependencies.
  config                      Manage local and global configuration.
  help                        Show help for commands.

General Options:
  -h, --help                  Show help.
  -v, --verbose               Give more output.
'
help_cmds="$(print -r -- "$pip_help" | __fzf_parse_help_commands)"
assert_ok 'help commands emit install' '[[ "$help_cmds" == *$'\''\n'\''install$'\''\t'\''* || "$help_cmds" == install$'\''\t'\''* ]]'
assert_ok 'help commands emit lock' '[[ "$help_cmds" == *"lock"$'\''\t'\''* ]]'
assert_ok 'help commands emit wrapped check' '[[ "$help_cmds" == *"check"$'\''\t'\''* ]]'
assert_ok 'help commands emit help verb' '[[ "$help_cmds" == *"help"$'\''\t'\''* ]]'
assert_ok 'help commands skip wrapped continuation' \
  '! print -r -- "$help_cmds" | command awk -F "\t" '\''$1=="dependencies"{found=1} END{exit !found}'\'''
assert_ok 'help commands skip dash options' '[[ "$help_cmds" != *"--help"* && "$help_cmds" != *"-v"* ]]'
help_all="$(print -r -- "$pip_help" | __fzf_parse_all_options_block)"
assert_ok 'all-options block keeps --help and install' \
  '[[ "$help_all" == *"--help"* && "$help_all" == *"install"$'\''\t'\''* ]]'

cobra_help='Usage:
  tool [command]

Available Commands:
  artifact    Manage OCI artifacts
  attach      Attach to a running container
  help        Help about any command

Flags:
  -h, --help   help for tool
'
cobra_cmds="$(print -r -- "$cobra_help" | __fzf_parse_help_commands)"
assert_ok 'Available Commands emit artifact' '[[ "$cobra_cmds" == *"artifact"$'\''\t'\''* ]]'
assert_ok 'Available Commands emit attach' '[[ "$cobra_cmds" == *"attach"$'\''\t'\''* ]]'

clap_help='Usage: tool [OPTIONS] <COMMAND>

Commands:
  build, b    Compile the current package
  run         Run a command
  help        Print help

Cache options:
  -n, --no-cache  Avoid the cache
'
clap_cmds="$(print -r -- "$clap_help" | __fzf_parse_help_commands)"
assert_ok 'clap alias uses primary name build' \
  'print -r -- "$clap_cmds" | command awk -F "\t" '\''$1=="build"{found=1} END{exit !found}'\'''
assert_ok 'clap Commands stop before Cache options' \
  '[[ "$clap_cmds" != *"--no-cache"* ]]'

pipx_help='usage: pipx [-h] [--version]

subcommands:
  Get help for commands with pipx COMMAND --help

  {install,uninstall,list}
    install             Install a package
    uninstall           Uninstall a package
    list                List installed packages

options:
  -h, --help            show this help message and exit
'
pipx_cmds="$(print -r -- "$pipx_help" | __fzf_parse_help_commands)"
assert_ok 'argparse subcommands emit install' \
  'print -r -- "$pipx_cmds" | command awk -F "\t" '\''$1=="install"{found=1} END{exit !found}'\'''
assert_ok 'argparse subcommands skip brace summary' \
  '! print -r -- "$pipx_cmds" | command awk -F "\t" '\''$1 ~ /^\{/{found=1} END{exit !found}'\'''
assert_ok 'argparse subcommands skip Get help prose' \
  '! print -r -- "$pipx_cmds" | command awk -F "\t" '\''$1=="Get"{found=1} END{exit !found}'\'''

if command -v pip >/dev/null 2>&1; then
  pip_entries="$(__fzf_build_entries pip '' 2>/dev/null)" || pip_entries=""
  assert_ok 'pip entries include install' '[[ "$pip_entries" == *"install"$'\''\t'\''* ]]'
  assert_ok 'pip entries include uninstall' '[[ "$pip_entries" == *"uninstall"$'\''\t'\''* ]]'
  assert_ok 'pip entries include freeze' '[[ "$pip_entries" == *"freeze"$'\''\t'\''* ]]'
  assert_ok 'pip entries still include --verbose' '[[ "$pip_entries" == *"--verbose"* ]]'
  LBUFFER='pip inst'
  __fzf_zle_token_state
  assert_ok 'pip inst is an incomplete sub prefix' \
    '! __fzf_rtfm_sub_token_complete pip inst "$lastw" "$LBUFFER"'
  LBUFFER='pip install'
  __fzf_zle_token_state
  assert_ok 'pip install is a complete sub' \
    '__fzf_rtfm_sub_token_complete pip install "$lastw" "$LBUFFER"'
else
  print -r -- "skip- pip not installed"
fi

bsd_fix="$(print -r -- '
NAME
ps - report
DESCRIPTION
       o   Unix options, which may be grouped and must be preceded by a dash.
EXAMPLES
       ps -e
SIMPLE PROCESS SELECTION
       a      Lift the BSD-style only-yourself restriction.
       -A     Select all processes.
       x      Lift the BSD-style must-have-a-tty restriction.
       u      Display user-oriented format.
  The selection options take as their argument either:
    a comma-separated list e.g. '"'"'-u root'"'"'
NOTES
       o      not a flag
' | __fzf_parse_bsd_letter_options)"
assert_ok 'BSD parse emits a/x/u' \
  'print -r -- "$bsd_fix" | command awk -F "\t" '\''$1=="a"{a=1}$1=="x"{x=1}$1=="u"{u=1} END{exit !(a&&x&&u)}'\'''
assert_ok 'BSD parse skips DESCRIPTION bullet o' \
  '! print -r -- "$bsd_fix" | command awk -F "\t" '\''$1=="o"{found=1} END{exit !found}'\'''
assert_ok 'BSD parse skips prose a comma-separated' \
  '[[ "$(print -r -- "$bsd_fix" | command awk -F "\t" '\''$1=="a"{c++} END{print c+0}'\'')" == 1 ]]'

# --- complete vs incomplete sub (query must not hide options) ---
LBUFFER='git sta'
__fzf_zle_token_state
git_sta_parsed="$(__fzf_get_cmd_and_sub)"
git_sta_cmd="${git_sta_parsed%%$'\t'*}"
git_sta_sub="${git_sta_parsed#*$'\t'}"
assert_ok 'git sta is an incomplete sub prefix' \
  '! __fzf_rtfm_sub_token_complete "$git_sta_cmd" "$git_sta_sub" "$lastw" "$LBUFFER"'

if command -v git >/dev/null 2>&1 && __fzf_man_topic_exists git-status; then
  LBUFFER='git status'
  __fzf_zle_token_state
  git_st_parsed="$(__fzf_get_cmd_and_sub)"
  git_st_cmd="${git_st_parsed%%$'\t'*}"
  git_st_sub="${git_st_parsed#*$'\t'}"
  assert_ok 'git status is a complete sub' \
    '__fzf_rtfm_sub_token_complete "$git_st_cmd" "$git_st_sub" "$lastw" "$LBUFFER"'
else
  print -r -- "skip- git-status man not available"
fi

LBUFFER='sv sta'
__fzf_zle_token_state
sv_sta_parsed="$(__fzf_get_cmd_and_sub)"
assert_ok 'sv sta is an incomplete verb prefix' \
  '! __fzf_rtfm_sub_token_complete sv sta "$lastw" "$LBUFFER"'

LBUFFER='ip a'
__fzf_zle_token_state
assert_ok 'ip a is an incomplete object prefix' \
  '! __fzf_rtfm_sub_token_complete ip a "$lastw" "$LBUFFER"'
LBUFFER='ip addr'
__fzf_zle_token_state
assert_ok 'ip addr is a complete object alias' \
  '__fzf_rtfm_sub_token_complete ip addr "$lastw" "$LBUFFER"'
LBUFFER='ip link'
__fzf_zle_token_state
assert_ok 'ip link is a complete object' \
  '__fzf_rtfm_sub_token_complete ip link "$lastw" "$LBUFFER"'

# --- docker ---
if command -v docker >/dev/null 2>&1; then
  docker_bad=""
  docker_ec=0
  docker_bad="$(__fzf_build_entries docker 'rtfm-not-a-real-sub-xyz' 2>/dev/null)" || docker_ec=$?
  assert_ok 'docker invalid sub returns empty/fail' \
    '[[ -z "$docker_bad" || $docker_ec -ne 0 ]]'
  docker_ps="$(__fzf_build_entries docker ps 2>/dev/null)" || docker_ps=""
  assert_ok 'docker ps offers --all' '[[ "$docker_ps" == *"--all"* ]]'
  assert_ok 'docker ps offers -a' '[[ "$docker_ps" == *"-a"* ]]'
  LBUFFER='docker p'
  __fzf_zle_token_state
  assert_ok 'docker p is an incomplete sub prefix' \
    '! __fzf_rtfm_sub_token_complete docker p "$lastw" "$LBUFFER"'
  LBUFFER='docker ps'
  __fzf_zle_token_state
  assert_ok 'docker ps is a complete sub' \
    '__fzf_rtfm_sub_token_complete docker ps "$lastw" "$LBUFFER"'
else
  print -r -- "skip- docker not installed"
fi

if command -v podman >/dev/null 2>&1; then
  LBUFFER='podman p'
  __fzf_zle_token_state
  assert_ok 'podman p is an incomplete sub prefix' \
    '! __fzf_rtfm_sub_token_complete podman p "$lastw" "$LBUFFER"'
  LBUFFER='podman ps'
  __fzf_zle_token_state
  if __fzf_build_entries podman ps 2>/dev/null | command grep -q -- '--all'; then
    assert_ok 'podman ps is a complete sub' \
      '__fzf_rtfm_sub_token_complete podman ps "$lastw" "$LBUFFER"'
  else
    print -r -- "skip- podman ps help not usable"
  fi
else
  print -r -- "skip- podman not installed"
fi

# --- used tokens disappear from the next picker ---
used_rows="$(print -r -- $'--author\tm\tprint author\n--all\tm\tall\n-l\tm\tlong' | __fzf_rtfm_filter_used_line_tokens 'ls --author -l ')"
assert_ok 'filter drops --author once used' '[[ "$used_rows" != *"--author"* ]]'
assert_ok 'filter drops -l once used' '[[ "$used_rows" != *$'\''\t-l\t'\''* && "$used_rows" != *$'\''\n-l\t'\''* && "$used_rows" != $'-l\t'* ]]'
assert_ok 'filter keeps unused --all' '[[ "$used_rows" == *"--all"* ]]'
combo_rows="$(print -r -- $'-A, --almost-all\tm\talmost\n--author\tm\tauth' | __fzf_rtfm_filter_used_line_tokens 'ls -A ')"
assert_ok 'filter drops combined form when short used' '[[ "$combo_rows" != *"almost-all"* ]]'

# --- docs prefer man; footers trimmed; preview file lookup ---
ls_docs="$(__fzf_rtfm_docs_text ls 2>/dev/null)" || ls_docs=""
assert_ok 'ls docs prefer man when available' \
  '[[ -n "$ls_docs" && ( "$ls_docs" == *"NAME"* || "$ls_docs" == *"SYNOPSIS"* || "$ls_docs" == *"ls"* ) ]]'
assert_ok 'ls docs trim AUTHOR/SEE ALSO/EXIT footers' \
  '[[ "$ls_docs" != *"REPORTING BUGS"* && "$ls_docs" != *"SEE ALSO"* && "$ls_docs" != *"EXIT STATUS"* ]]'
assert_ok 'ls wants files without loading full docs path' \
  '__fzf_rtfm_cmd_wants_files ls'

if command -v ps >/dev/null 2>&1; then
  ps_entries="$(__fzf_build_entries ps '' 'ps ' 2>/dev/null)" || ps_entries=""
  assert_ok 'ps offers selection options from man or --help all' \
    '[[ "$ps_entries" == *"-e"* || "$ps_entries" == *"-A"* || "$ps_entries" == *"--deselect"* || "$ps_entries" == *"--pid"* ]]'
  assert_ok 'ps offers BSD letters a/x/u' \
    'print -r -- "$ps_entries" | command awk -F "\t" '\''$1=="a"{a=1}$1=="x"{x=1}$1=="u"{u=1} END{exit !(a&&x&&u)}'\'''
  LBUFFER='ps a'
  __fzf_zle_token_state
  assert_ok 'ps a is a BSD flag query, not a subcommand' \
    '! __fzf_rtfm_sub_token_complete ps a "$lastw" "$LBUFFER"'
  ps_used="$(print -r -- $'a\tm\tall tty\nx\tm\tno tty\n-e\tm\tall' | __fzf_rtfm_filter_used_line_tokens 'ps aux ')"
  assert_ok 'filter splits aux into a/u/x' \
    'print -r -- "$ps_used" | command awk -F "\t" '\''$1=="a"{a=1}$1=="x"{x=1}$1=="-e"{e=1} END{exit !(!a && !x && e)}'\'''
  ps_w="$(print -r -- $'w\tm\twide\na\tm\tall\nx\tm\tno tty' | __fzf_rtfm_filter_used_line_tokens 'ps auxwww ')"
  assert_ok 'filter keeps repeatable w after auxwww' \
    'print -r -- "$ps_w" | command awk -F "\t" '\''$1=="w"{w=1}$1=="a"{a=1}$1=="x"{x=1} END{exit !(w && !a && !x)}'\'''
  LBUFFER='ps -A u '
  assert_ok 'ps -A u is not a subcommand page' \
    '[[ "$(__fzf_get_cmd_and_sub)" == $'\''ps\t'\'' ]]'
  LBUFFER='ps au'
  __fzf_zle_token_state
  assert_ok 'ps au has empty sub' \
    '[[ "$(__fzf_get_cmd_and_sub)" == $'\''ps\t'\'' ]]'
  prefix_rest='ps' lastw=''
  __fzf_apply_bsd_letter a
  assert_ok 'bsd letter starts cluster without trailing space' \
    '[[ "$LBUFFER" == "ps a" ]]'
  LBUFFER='ps a'
  __fzf_zle_token_state
  __fzf_apply_bsd_letter u
  assert_ok 'bsd letter appends to cluster' \
    '[[ "$LBUFFER" == "ps au" ]]'
  LBUFFER='ps au'
  __fzf_zle_token_state
  __fzf_apply_bsd_letter f
  __fzf_zle_token_state
  __fzf_apply_bsd_letter x
  __fzf_zle_token_state
  __fzf_apply_bsd_letter w
  __fzf_zle_token_state
  __fzf_apply_bsd_letter w
  __fzf_zle_token_state
  __fzf_apply_bsd_letter w
  assert_ok 'bsd letters build aufxwww' \
    '[[ "$LBUFFER" == "ps aufxwww" ]]'
  LBUFFER='ps -A '
  __fzf_zle_token_state
  __fzf_apply_bsd_letter u
  assert_ok 'bsd letter after dash option starts new cluster' \
    '[[ "$LBUFFER" == "ps -A u" ]]'
  assert_ok 'ps synopsis [option ...] does not imply files' \
    '! __fzf_rtfm_cmd_wants_files ps'
else
  print -r -- "skip- ps not installed"
fi
man_rows_ls="$(__fzf_rtfm_entries_to_man_rows "$(__fzf_build_entries ls '' 2>/dev/null)" 'ls --author ')"
assert_ok 'ls man_rows drop used --author' '[[ "$man_rows_ls" != *"--author"* ]]'
assert_ok 'ls man_rows neutralize apostrophes in desc' \
  '[[ "$(print -r -- "$man_rows_ls" | command awk -F"\t" "\$3 ~ /'\''/ {c++} END{print c+0}")" == 0 ]]'

if command -v docker >/dev/null 2>&1; then
  docker_docs="$(__fzf_rtfm_docs_text docker ps 2>/dev/null)" || docker_docs=""
  assert_ok 'docker ps docs available via man or help' \
    '[[ -n "$docker_docs" ]]'
  __fzf_rtfm_ensure_preview_script
  _descf=$(mktemp "${TMPDIR:-/tmp}/rtfm-desc.XXXXXX")
  print -r -- $'--format\tm\tFormat: table TEMPLATE and Do not break' >"$_descf"
  _pout="$("$__fzf_rtfm_preview_script" --format m "$_descf")"
  assert_ok 'preview looks up desc from file' \
    '[[ "$_pout" == *TEMPLATE* ]]'
  command rm -f "$_descf"
else
  print -r -- "skip- docker docs/preview tests"
fi

# --- zoomed listings show child names only ---
_td=$(mktemp -d "${TMPDIR:-/tmp}/rtfm-zoom.XXXXXX")
mkdir -p "$_td/src/nested"
print -r -- x >"$_td/src/file"
lastw=''
zoom_rows="$(__fzf_tab_immediate_file_rows "$_td/src" all 1 1)"
assert_ok 'zoom list shows basename file' \
  'print -r -- "$zoom_rows" | command awk -F "\t" '\''$1=="file" && $2=="f" {found=1} END{exit !found}'\'''
assert_ok 'zoom list keeps full path in field 3' \
  'print -r -- "$zoom_rows" | command awk -F "\t" -v p="'"$_td/src/file"'" '\''$1=="file" && $3==p {found=1} END{exit !found}'\'''
assert_ok 'zoom list does not show parent/child in field 1' \
  '[[ "$zoom_rows" != *$'\''\n'\''src/file$'\''\t'\''* && "$zoom_rows" != src/file$'\''\t'\''* ]]'
_row=$'file\tf\t'"$_td/src/file"
assert_ok 'row apply token uses full path' \
  '[[ "$(__fzf_rtfm_row_apply_token "$_row")" == "'"$_td/src/file"'" ]]'
assert_ok 'zoom prompt is current dir only' \
  '[[ "$(__fzf_rtfm_zoom_prompt "'$_td'/src")" == "src/ > " ]]'
assert_ok 'zoom prompt for root' \
  '[[ "$(__fzf_rtfm_zoom_prompt /)" == "/ > " ]]'
cwd_rows="$(cd "$_td" && lastw='' && __fzf_tab_immediate_file_rows . all 1 1)"
assert_ok 'cwd list keeps src as both display and path' \
  'print -r -- "$cwd_rows" | command awk -F "\t" '\''$1=="src" && $3=="src" {found=1} END{exit !found}'\'''
command rm -rf "$_td"

# --- shared word split handles quotes; matches token state ---
LBUFFER="git commit -m 'hello world' "
__fzf_zle_token_state
assert_ok 'quoted arg keeps lastw empty after trailing space' '[[ -z "$lastw" ]]'
assert_ok 'quoted arg stays in prefix_rest' '[[ "$prefix_rest" == *"hello world"* ]]'
_wsplit="$(__fzf_rtfm_wsplit "cmd -m 'a b'")"
assert_ok 'wsplit keeps quoted phrase as one word' \
  'print -r -- "$_wsplit" | command awk '\''BEGIN{n=0} NF{n++} END{exit !(n==3)}'\'''

# --- untrace clears functions -t ---
__fzf_rtfm_untrace_probe() { :; }
functions -t __fzf_rtfm_untrace_probe
__fzf_rtfm_untrace
assert_ok 'untrace clears functions -t flag' \
  '[[ -z "$(functions -t 2>/dev/null | command rg -F -- "__fzf_rtfm_untrace_probe" || true)" ]]'

# --- Tab-continue rebuild writes expected state files ---
_rb=$(mktemp -d "${TMPDIR:-/tmp}/rtfm-rb.XXXXXX")
LBUFFER='ls --author '
lastw=''
prefix_rest='ls --author'
__fzf_rtfm_tab_continue_rebuild "$_rb" all 'ls > '
assert_ok 'rebuild use_man is 1 for ls' '[[ "$(command cat -- "$_rb/use_man")" == 1 ]]'
assert_ok 'rebuild man_rows drop used --author' \
  '[[ "$(command cat -- "$_rb/man_rows")" != *"--author"* ]]'
assert_ok 'rebuild show_prompt is ls' \
  '[[ "$(command cat -- "$_rb/show_prompt")" == "ls > " ]]'
command rm -rf "$_rb"

_rb=$(mktemp -d "${TMPDIR:-/tmp}/rtfm-rb.XXXXXX")
mkdir -p "$_rb/fixture/src/nested" "$_rb/out"
LBUFFER='cd src/'
lastw='src/'
prefix_rest='cd'
( cd "$_rb/fixture" && __fzf_rtfm_tab_continue_rebuild "$_rb/out" dirs 'cd > ' )
assert_ok 'rebuild cd src/ is dirs mode' '[[ "$(command cat -- "$_rb/out/list_mode")" == dirs ]]'
assert_ok 'rebuild list_dir is src' \
  '[[ "$(command cat -- "$_rb/out/list_dir")" == src || "$(command cat -- "$_rb/out/list_dir")" == src/ || "$(command cat -- "$_rb/out/list_dir")" == ./src ]]'
command rm -rf "$_rb"

# --- generated lister matches immediate_file_rows shape ---
_td=$(mktemp -d "${TMPDIR:-/tmp}/rtfm-lister.XXXXXX")
mkdir -p "$_td/src/nested"
print -r -- x >"$_td/src/file"
_state=$(mktemp "${TMPDIR:-/tmp}/rtfm-st.XXXXXX")
_man=$(mktemp "${TMPDIR:-/tmp}/rtfm-mn.XXXXXX")
_lister=$(mktemp "${TMPDIR:-/tmp}/rtfm-ls.XXXXXX")
{
  print -r -- "$_td/src"
  print -r -- 1
  print -r -- 1
  print -r -- 0
  print -r -- all
} >"$_state"
: >"$_man"
__fzf_rtfm_write_lister "$_lister" "$_state" "$_man" 0
command chmod +x "$_lister"
_lister_out="$("$_lister")"
_imm_out="$(lastw='' && __fzf_tab_immediate_file_rows "$_td/src" all 1 1)"
assert_ok 'lister shows basename file' \
  'print -r -- "$_lister_out" | command awk -F "\t" '\''$1=="file" && $2=="f" {found=1} END{exit !found}'\'''
assert_ok 'lister field 3 is full path' \
  'print -r -- "$_lister_out" | command awk -F "\t" -v p="'"$_td/src/file"'" '\''$1=="file" && $3==p {found=1} END{exit !found}'\'''
_expect=$'file\tf\t'"$_td/src/file"
assert_ok 'lister and immediate_file_rows agree on file row' \
  'print -r -- "$_lister_out" | command rg -F -- "$_expect" >/dev/null && print -r -- "$_imm_out" | command rg -F -- "$_expect" >/dev/null'
command rm -rf "$_td"
command rm -f "$_state" "$_man" "$_lister"

# --- xtrace must not dump man entries above fzf ---
_xt=$(mktemp "${TMPDIR:-/tmp}/rtfm-xt.XXXXXX")
__fzf_rtfm_xtrace_quiet_probe() {
  setopt localoptions noxtrace noverbose
  local _entries
  _entries=$'--color[=WHEN]\tWHEN '\''always'\'' TIME_STYLE'
}
() {
  setopt localoptions xtrace
  __fzf_rtfm_xtrace_quiet_probe
} 2>"$_xt"
assert_ok 'noxtrace hides _entries assignment' \
  '! command rg -q -- "TIME_STYLE|always" "$_xt"'
command rm -f "$_xt"

# --- path scheme / help / preview ---
assert_ok 'path scheme array is declared' '[[ -n "${__fzf_rtfm_merged_path_scheme+x}" ]]'
assert_ok 'help script executable' '[[ -x "$__fzf_rtfm_help_script" ]]'
assert_ok 'preview script executable' '[[ -x "$__fzf_rtfm_preview_script" ]]'

print -r -- ""
print -r -- "passed=$PASS failed=$FAIL"
(( FAIL == 0 ))
