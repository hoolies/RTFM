#!/usr/bin/env zsh
# Functionality suite for RTFM (no interactive fzf).
# Every change must leave this file green: zsh tests/rtfm-unit.zsh
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

# --- paths with spaces are one shell word (backslash-escaped) ---
assert_ok 'quote escapes spaces in a directory' \
  '[[ "$(__fzf_rtfm_shell_quote_path "/this is an example/")" == "/this\\ is\\ an\\ example/" ]]'
assert_ok 'quote leaves a command or subcommand alone' \
  '[[ "$(__fzf_rtfm_shell_quote_path nosuchcmd)" == nosuchcmd && "$(__fzf_rtfm_shell_quote_path "no-such&sub")" == "no-such&sub" ]]'
assert_ok 'quote escapes & in a directory path' \
  '[[ "$(__fzf_rtfm_shell_quote_path "L&D/")" == "L\\&D/" ]]'
assert_ok 'quote leaves an option alone' \
  '[[ "$(__fzf_rtfm_shell_quote_path "--color[=WHEN]")" == "--color[=WHEN]" ]]'
assert_ok 'quote keeps a leading tilde expandable' \
  '[[ "$(__fzf_rtfm_shell_quote_path "~/My Dir/file")" == "~/My\\ Dir/file" ]]'
assert_ok 'unquote restores an escaped path' \
  '[[ "$(__fzf_rtfm_shell_unquote "/this\\ is\\ an\\ example/")" == "/this is an example/" ]]'
_sq="$(__fzf_rtfm_shell_unquote "'/this is an example/'")"
assert_ok 'unquote restores a single-quoted path' \
  '[[ "$_sq" == "/this is an example/" ]]'
lastw='src/my\ dir/'
assert_ok 'resolve joins onto an escaped directory prefix' \
  '[[ "$(__fzf_rtfm_resolve_path_pick child)" == "src/my dir/child" ]]'
prefix_rest='cd'
LBUFFER='cd '
__fzf_apply_dir_pick '/this is an example'
assert_ok 'dir pick inserts an escaped directory with a trailing slash' \
  '[[ "$LBUFFER" == "cd /this\\ is\\ an\\ example/" ]]'
prefix_rest='cp'
LBUFFER='cp '
lastw=''
__fzf_apply_dir_pick 'my dir'
assert_ok 'cp dir pick finishes the argument' \
  '[[ "$LBUFFER" == "cp my\\ dir/ " ]]'
__fzf_zle_token_state
assert_ok 'cp dir pick is not a directory prefix' \
  '[[ -z "$lastw" ]]'
prefix_rest='sudo cp'
LBUFFER='sudo cp '
__fzf_apply_dir_pick 'L&D'
assert_ok 'sudo cp dir pick escapes and finishes the argument' \
  '[[ "$LBUFFER" == "sudo cp L\\&D/ " ]]'
prefix_rest='pushd'
LBUFFER='pushd '
__fzf_apply_dir_pick 'mydir'
assert_ok 'pushd dir pick stays open' \
  '[[ "$LBUFFER" == "pushd mydir/" ]]'
prefix_rest='cat'
lastw=''
__fzf_apply_pick './my file.txt'
assert_ok 'file pick inserts an escaped path and a trailing space' \
  '[[ "$LBUFFER" == "cat ./my\\ file.txt " ]]'
prefix_rest='ls'
lastw=''
__fzf_apply_pick '--color[=WHEN]'
assert_ok 'option pick is not escaped' \
  '[[ "$LBUFFER" == "ls --color[=WHEN] " ]]'
LBUFFER='cd /this\ is\ an\ example/'
__fzf_zle_token_state
assert_ok 'escaped directory is still a directory prefix' \
  '__fzf_rtfm_is_dir_prefix'
assert_ok 'escaped directory is pathlike' \
  '__fzf_last_word_is_pathlike "$lastw"'
LBUFFER='git my\ sub '
_cmdsub="$(__fzf_get_cmd_and_sub)"
assert_ok 'help lookup unquotes an escaped subcommand' \
  '[[ "${_cmdsub#*$'\''\t'\''}" == "my sub" ]]'
LBUFFER='git status'
__fzf_zle_token_state
assert_ok 'quoted subcommand word still counts as complete' \
  '__fzf_rtfm_sub_token_complete git status "'\''status'\''" "git status"'
_space_rows=$'my file\tf\t./my file'
_space_out="$(print -r -- "$_space_rows" | __fzf_rtfm_filter_used_line_tokens 'cat ./my\ file ')"
assert_ok 'used-token filter drops an escaped path' \
  '[[ -z "$_space_out" ]]'

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

# curl-style: example lines and "can be used several times" restatements
# must not become extra -F / --form rows. --form-string stays distinct.
curl_form="$(print -r -- '
       -F, --form <name=content>
              For HTTP POST multipart forms.
              -F "name=daniel;type=text/foo"
              -F "file=@localfile;filename=nameinpost"
              --form can be used several times in a command line
       --form-string <name=string>
              Similar to --form except the value is literal.
              --form-string can be used several times in a command line
       --form-escape
              Escape multipart form names.
' | __fzf_parse_dash_options_block)"
assert_ok 'curl -F heading appears once' \
  '[[ "$(print -r -- "$curl_form" | command awk -F "\t" '\''$1 ~ /(^| )-F([, ]|$)/ || $1 == "-F"{c++} END{print c+0}'\'')" == 1 ]]'
assert_ok 'curl --form restatement is not its own row' \
  '! print -r -- "$curl_form" | command awk -F "\t" '\''$1=="--form"{found=1} END{exit !found}'\'''
assert_ok 'curl example -F quoted line is not its own row' \
  '! print -r -- "$curl_form" | command awk -F "\t" '\''$1 ~ /daniel/{found=1} END{exit !found}'\'''
assert_ok 'curl --form-string stays distinct' \
  'print -r -- "$curl_form" | command awk -F "\t" '\''index($1,"--form-string")==1{found=1} END{exit !found}'\'''
assert_ok 'curl --form-escape stays distinct' \
  'print -r -- "$curl_form" | command awk -F "\t" '\''index($1,"--form-escape")==1{found=1} END{exit !found}'\'''
dup_help="$(print -r -- '
       -h, --help
              first help
       -h, --help
              second help
       -v, --verbose
              verbose mode
' | __fzf_parse_dash_options_block)"
assert_ok 'duplicate -h,--help collapses to one row' \
  '[[ "$(print -r -- "$dup_help" | command awk -F "\t" '\''$1 ~ /--help/{c++} END{print c+0}'\'')" == 1 ]]'
assert_ok 'uniq keeps first -h description' \
  'print -r -- "$dup_help" | command awk -F "\t" '\''$1 ~ /--help/ && $2 ~ /first/{found=1} END{exit !found}'\'''
assert_ok 'uniq still emits --verbose' \
  '[[ "$dup_help" == *"--verbose"* ]]'

if command -v curl >/dev/null 2>&1; then
  curl_entries="$(__fzf_build_entries curl '' 2>/dev/null)" || curl_entries=""
  if [[ -n "$curl_entries" ]]; then
    assert_ok 'live curl has a single -F row' \
      '[[ "$(print -r -- "$curl_entries" | command awk -F "\t" '\''$1 ~ /(^| )-F([, ]|$)/ || $1 == "-F"{c++} END{print c+0}'\'')" == 1 ]]'
  else
    print -r -- "skip- curl entries empty"
  fi
else
  print -r -- "skip- curl not installed"
fi

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
_spaced=$(mktemp -d "${TMPDIR:-/tmp}/rtfm-spaced.XXXXXX")
mkdir -p -- "$_spaced/this is an example/nested"
LBUFFER='cd this\ is\ an\ example/'
__fzf_zle_token_state
assert_ok 'escaped prefix lists the real directory' \
  '( cd -- "$_spaced" && __fzf_tab_path_token_dir_base && [[ "$dir" == "this is an example" || "$dir" == "this is an example/" ]] )'
_space_list="$(cd -- "$_spaced" && __fzf_tab_immediate_file_rows "this is an example" dirs 1 1)"
assert_ok 'listing a spaced directory shows its child' \
  'print -r -- "$_space_list" | command awk -F "\t" '\''$1=="nested" {found=1} END{exit !found}'\'''
command rm -rf -- "$_td" "$_spaced"

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

_rb=$(mktemp -d "${TMPDIR:-/tmp}/rtfm-rb.XXXXXX")
mkdir -p "$_rb/fixture/src/nested" "$_rb/out"
print -r -- x >"$_rb/fixture/src/file"
LBUFFER='cp src/'
lastw='src/'
prefix_rest='cp'
( cd "$_rb/fixture" && __fzf_rtfm_tab_continue_rebuild "$_rb/out" all 'cp > ' )
assert_ok 'rebuild cp src/ lists files and directories' \
  '[[ "$(command cat -- "$_rb/out/list_mode")" == all ]]'
assert_ok 'rebuild cp src/ includes the file' \
  'command awk -F "\t" '\''$1=="file" && $2=="f" {found=1} END{exit !found}'\'' "$_rb/out/file_rows"'
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

# --- wrappers: skip flags and env assignments ---
LBUFFER='sudo -u root docker ps '
assert_ok 'sudo -u root docker ps sees docker' \
  '[[ "$(__fzf_get_cmd_and_sub)" == docker$'\''\t'\''ps ]]'
LBUFFER='env FOO=1 ls '
assert_ok 'env FOO=1 ls sees ls' \
  '[[ "$(__fzf_get_cmd_and_sub)" == ls$'\''\t'\'' ]]'
LBUFFER='nice -n 19 make '
assert_ok 'nice -n 19 make sees make' \
  '[[ "$(__fzf_get_cmd_and_sub)" == make$'\''\t'\'' ]]'
LBUFFER='doas -u root sv status '
assert_ok 'doas -u root sv status offers services' \
  '__fzf_sv_should_offer_services "$LBUFFER"'
assert_ok 'sudo -u without a user is needarg' \
  '[[ "$(__fzf_rtfm_scan_command_words sudo -u)" == needarg ]]'

# --- BSD letter split is only for ps ---
_plain=$'s\tm\tshort\nu\tm\tuntracked\n--long\tm\tlong'
_plain_out="$(print -r -- "$_plain" | __fzf_rtfm_filter_used_line_tokens 'git status ')"
assert_ok 'git status does not hide letter s' \
  'print -r -- "$_plain_out" | command awk -F "\t" '\''$1=="s"{found=1} END{exit !found}'\'''
assert_ok 'git status does not hide letter u' \
  'print -r -- "$_plain_out" | command awk -F "\t" '\''$1=="u"{found=1} END{exit !found}'\'''

# --- paths only when the text names a file, not any positional word ---
assert_ok 'FILE token wants files' \
  '__fzf_rtfm_text_wants_files "Usage: install [OPTION]... FILE"'
assert_ok 'positional message does not want files' \
  '! __fzf_rtfm_text_wants_files $'"'"'SYNOPSIS\n       git commit [options] message'"'"

# --- help probes do not read the caller stdin ---
_help_in="$(printf 'LEAK\n' | __fzf_rtfm_capture_help sh -c 'read line || line=EMPTY; printf "%s" "$line"')"
assert_ok 'help probe stdin is /dev/null' '[[ "$_help_in" == EMPTY ]]'

# --- generated sh quoting ---
_sq="$(__fzf_rtfm_sh_sq "a'b")"
if [[ "$_sq" == "'a'\\''b'" ]]; then
  print -r -- "ok  - posix single quote escapes apostrophe"
  PASS=$((PASS + 1))
else
  print -r -- "FAIL- posix single quote escapes apostrophe (got $_sq)"
  FAIL=$((FAIL + 1))
fi

# --- empty picker hands Tab back ---
__fzf_rtfm_prev_tab_widget=expand-or-complete
zle() { print -r -- "called:$*"; }
_fb="$(__fzf_rtfm_fallback_tab)"
zle() { :; }
assert_ok 'fallback calls the previous Tab widget' '[[ "$_fb" == "called:expand-or-complete" ]]'

# --- preview hides secret-looking files ---
_sec=$(mktemp -d "${TMPDIR:-/tmp}/rtfm-sec.XXXXXX")
print -r -- 'SUPERSECRET' >"$_sec/.env"
print -r -- 'hello-preview' >"$_sec/note.txt"
_env_out="$("$__fzf_rtfm_preview_script" "$_sec/.env" f)"
_note_out="$("$__fzf_rtfm_preview_script" "$_sec/note.txt" f)"
assert_ok 'preview hides .env contents' \
  '[[ "$_env_out" == *hidden* && "$_env_out" != *SUPERSECRET* ]]'
assert_ok 'preview still shows a normal text file' \
  '[[ "$_note_out" == *hello-preview* ]]'
command rm -rf -- "$_sec"

# --- command name vs arguments ---
LBUFFER=''
assert_ok 'empty line completes a command name' '__fzf_tab_completing_command_name'
LBUFFER='gi'
assert_ok 'partial command completes a command name' '__fzf_tab_completing_command_name'
LBUFFER='git '
assert_ok 'command plus space is arguments' '! __fzf_tab_completing_command_name'
LBUFFER='sudo '
assert_ok 'sudo plus space still completes the command' '__fzf_tab_completing_command_name'
LBUFFER='sudo ls '
assert_ok 'sudo ls plus space is arguments' '! __fzf_tab_completing_command_name'
LBUFFER='./src'
__fzf_zle_token_state
assert_ok 'path-shaped first word is still a path' \
  '__fzf_tab_completing_command_name && __fzf_last_word_is_pathlike "$lastw"'
_cmd_hits="$(printf '%s\n' git gitk go | __fzf_tab_command_matches gi)"
assert_ok 'command prefix matches git and gitk' \
  'print -r -- "$_cmd_hits" | command awk '\''$0=="git"{g=1} $0=="gitk"{k=1} $0=="go"{o=1} END{exit !(g && k && !o)}'\'''
assert_ok 'shell words include cd and source' \
  '__fzf_rtfm_cmd_picker_shell_words | command rg -x -q cd && __fzf_rtfm_cmd_picker_shell_words | command rg -x -q source'
assert_ok 'normalize query collapses spaces' \
  '[[ "$(__fzf_rtfm_normalize_query "  git   sta  ")" == "git sta" ]]'

# --- wrappers ---
LBUFFER='command ls -l '
assert_ok 'command wrapper sees ls' \
  '[[ "$(__fzf_get_cmd_and_sub)" == ls$'\''\t'\'' ]]'
LBUFFER='builtin cd '
assert_ok 'builtin wrapper sees cd' \
  '[[ "$(__fzf_get_cmd_and_sub)" == cd$'\''\t'\'' ]]'
LBUFFER='time -f %e ls '
assert_ok 'time -f sees ls' \
  '[[ "$(__fzf_get_cmd_and_sub)" == ls$'\''\t'\'' ]]'
LBUFFER='nohup make '
assert_ok 'nohup wrapper sees make' \
  '[[ "$(__fzf_get_cmd_and_sub)" == make$'\''\t'\'' ]]'
LBUFFER='sudo -- ls '
assert_ok 'sudo -- ends wrapper options' \
  '[[ "$(__fzf_get_cmd_and_sub)" == ls$'\''\t'\'' ]]'
LBUFFER='env FOO=1 BAR=2 ls '
assert_ok 'env assignments are not the command' \
  '[[ "$(__fzf_get_cmd_and_sub)" == ls$'\''\t'\'' ]]'

# --- which commands take path arguments ---
assert_ok 'cp takes files' '__fzf_rtfm_cmd_wants_files cp'
assert_ok 'mv takes files' '__fzf_rtfm_cmd_wants_files mv'
assert_ok 'rm takes files' '__fzf_rtfm_cmd_wants_files rm'
assert_ok 'cp still takes files when the sub looks like a path' \
  '__fzf_rtfm_cmd_wants_files cp src/'
unset '__fzf_rtfm_wants_files_cache[git]'
assert_ok 'git is not a hardcoded path command' \
  '! __fzf_rtfm_cmd_wants_files git'
assert_ok 'docker run takes files' '__fzf_rtfm_cmd_wants_files docker run'
assert_ok 'docker ps does not take files' '! __fzf_rtfm_cmd_wants_files docker ps'
assert_ok 'usage FILE wants files' \
  '__fzf_rtfm_text_wants_files "copy <file> <path> <dir> filename"'
assert_ok 'DIRECTORY token wants files' \
  '__fzf_rtfm_text_wants_files "ln [OPTION]... TARGET... DIRECTORY"'
assert_ok 'ln is a hardcoded path command' \
  '__fzf_rtfm_cmd_wants_files ln'
assert_ok 'rsync is a hardcoded path command' \
  '__fzf_rtfm_cmd_wants_files rsync'
assert_ok 'plain prose does not want files' \
  '! __fzf_rtfm_text_wants_files "just a message"'
assert_ok 'compact whitespace' '[[ "$(__fzf_compact_ws "  a   b  ")" == "a b" ]]'

# --- path token classification ---
lastw=''
assert_ok 'empty token is not path-only' '! __fzf_rtfm_path_only'
lastw='--color'
assert_ok 'an option is not a directory prefix' '! __fzf_rtfm_is_dir_prefix'
assert_ok 'an option is not pathlike' '! __fzf_last_word_is_pathlike "$lastw"'
assert_ok 'an option is not path-only' '! __fzf_rtfm_path_only'
lastw='/'
assert_ok 'root is a directory prefix' '__fzf_rtfm_is_dir_prefix'
lastw='./'
assert_ok 'dot-slash is a directory prefix' '__fzf_rtfm_is_dir_prefix'
lastw='../'
assert_ok 'dot-dot-slash is a directory prefix' '__fzf_rtfm_is_dir_prefix'
assert_ok 'tilde is pathlike' '__fzf_last_word_is_pathlike "~"'
assert_ok 'quote leaves a builtin name alone' \
  '[[ "$(__fzf_rtfm_shell_quote_path "[[")" == "[[" ]]'
assert_ok 'quote leaves g++ alone' \
  '[[ "$(__fzf_rtfm_shell_quote_path "g++")" == "g++" ]]'
assert_ok 'quote leaves a long option with a placeholder alone' \
  '[[ "$(__fzf_rtfm_shell_quote_path "--exec-path[=<path>]")" == "--exec-path[=<path>]" ]]'
assert_ok 'empty pick is rejected' '! __fzf_apply_pick ""'

# --- inserting a row ---
assert_ok 'first option form keeps the short flag' \
  '[[ "$(__fzf_rtfm_first_option_form "-A, --all")" == "-A" ]]'
assert_ok 'spaced option form keeps the short flag' \
  '[[ "$(__fzf_rtfm_first_option_form "-A --all")" == "-A" ]]'
assert_ok 'a single long option stays whole' \
  '[[ "$(__fzf_rtfm_first_option_form "--verbose")" == "--verbose" ]]'
assert_ok 'an option with a value stays whole' \
  '[[ "$(__fzf_rtfm_first_option_form "-C <path>")" == "-C <path>" ]]'
assert_ok 'a subcommand is not rewritten' \
  '[[ "$(__fzf_rtfm_first_option_form status)" == status ]]'
prefix_rest='ls'
LBUFFER='ls '
lastw=''
__fzf_apply_mixed_pick $'-A, --all\tm\talmost all'
assert_ok 'mixed option pick inserts the short flag' \
  '[[ "$LBUFFER" == "ls -A " ]]'
prefix_rest='git'
LBUFFER='git '
lastw=''
__fzf_apply_mixed_pick $'status\tm\tshow the working tree'
assert_ok 'mixed subcommand pick does not add a slash' \
  '[[ "$LBUFFER" == "git status " ]]'
LBUFFER='ps au'
prefix_rest='ps'
lastw='au'
__fzf_apply_mixed_pick $'x\tm\tprocesses'
assert_ok 'mixed BSD letter extends the cluster' \
  '[[ "$LBUFFER" == "ps aux" ]]'
LBUFFER='keep'
prefix_rest='keep'
assert_ok 'fzf abort leaves the line' \
  '__fzf_tab_finish_fzf_pick 2 nope __fzf_apply_pick && [[ "$LBUFFER" == keep ]]'
assert_ok 'fzf failure leaves the line' \
  '! __fzf_tab_finish_fzf_pick 1 nope __fzf_apply_pick && [[ "$LBUFFER" == keep ]]'
assert_ok 'empty fzf pick leaves the line' \
  '__fzf_tab_finish_fzf_pick 0 "" __fzf_apply_pick && [[ "$LBUFFER" == keep ]]'

# --- directory and file arguments ---
_fx=$(mktemp -d "${TMPDIR:-/tmp}/rtfm-fn.XXXXXX")
mkdir -p "$_fx/subdir/nested" "$_fx/empty" "$_fx/build"
print -r -- 'note-body' >"$_fx/note.txt"
print -r -- 'secret' >"$_fx/.secret"
print -r -- 'built' >"$_fx/build/out"
print -r -- 'child' >"$_fx/srcfile"
mkdir -p "$_fx/src"
print -r -- 'inside' >"$_fx/src/file"
prefix_rest='cp'
LBUFFER='cp '
lastw=''
__fzf_apply_mixed_pick $'note.txt\tf\t'"$_fx/note.txt"
assert_ok 'mixed file pick inserts the path and a space' \
  '[[ "$LBUFFER" == "cp '"$_fx"'/note.txt " ]]'
prefix_rest='cp'
LBUFFER='cp '
lastw=''
__fzf_apply_mixed_pick $'subdir\tf\t'"$_fx/subdir"
assert_ok 'mixed dir pick for cp finishes the argument' \
  '[[ "$LBUFFER" == "cp '"$_fx"'/subdir/ " ]]'
prefix_rest='cd'
LBUFFER='cd '
lastw=''
__fzf_apply_mixed_pick $'subdir\tf\t'"$_fx/subdir"
assert_ok 'mixed dir pick for cd stays open' \
  '[[ "$LBUFFER" == "cd '"$_fx"'/subdir/" ]]'
prefix_rest='mv'
LBUFFER='mv '
lastw=''
__fzf_apply_dir_pick 'src'
assert_ok 'mv dir pick finishes the argument' '[[ "$LBUFFER" == "mv src/ " ]]'
prefix_rest='rm'
LBUFFER='rm '
lastw=''
__fzf_apply_dir_pick 'src'
assert_ok 'rm dir pick finishes the argument' '[[ "$LBUFFER" == "rm src/ " ]]'
prefix_rest='mkdir'
LBUFFER='mkdir '
lastw=''
__fzf_apply_dir_pick 'newname'
assert_ok 'mkdir dir pick finishes the argument' '[[ "$LBUFFER" == "mkdir newname/ " ]]'
prefix_rest='cp'
LBUFFER='cp '
lastw=''
__fzf_apply_pick 'empty/'
assert_ok 'empty directory insert has a trailing space' \
  '[[ "$LBUFFER" == "cp empty/ " ]]'
_spaced_file="$(cd "$_fx" && __fzf_rtfm_shell_quote_path "note.txt")"
assert_ok 'plain existing file is not over-quoted' '[[ "$_spaced_file" == note.txt ]]'
print -r -- x >"$_fx/my file.txt"
_spaced_file="$(cd "$_fx" && __fzf_rtfm_shell_quote_path "my file.txt")"
assert_ok 'existing spaced file is escaped' '[[ "$_spaced_file" == "my\\ file.txt" ]]'

# --- listings ---
_dirs="$(__fzf_rtfm_list_paths "$_fx" dirs 1 1)"
assert_ok 'dirs mode skips files' '[[ "$_dirs" != *note.txt && "$_dirs" == *subdir* ]]'
_hidden="$(__fzf_rtfm_list_paths "$_fx" all 1 0)"
assert_ok 'hidden mode off skips dotfiles' '[[ "$_hidden" != *.secret* ]]'
_shown="$(__fzf_rtfm_list_paths "$_fx" all 1 1)"
assert_ok 'hidden mode on includes dotfiles' '[[ "$_shown" == *.secret* ]]'
_rows="$(lastw='' && __fzf_tab_immediate_file_rows "$_fx" all 1 1)"
assert_ok 'listings do not offer ..' \
  '[[ "$_rows" != *$'\''\t..\t'\''* && "$_rows" != ..$'\''\t'\''* ]]'
assert_ok 'non-empty directory has entries' \
  '__fzf_rtfm_dir_has_entries "'"$_fx"'/subdir" all 1'
assert_ok 'empty directory has no entries' \
  '! __fzf_rtfm_dir_has_entries "'"$_fx"'/empty" all 1'
assert_ok 'a file is not a directory listing' \
  '! __fzf_rtfm_dir_has_entries "'"$_fx"'/note.txt" all 1'
_dot="$(cd "$_fx" && lastw='./' && __fzf_tab_immediate_file_rows . all 1 1)"
assert_ok 'typed ./ keeps the dot-slash on the row' \
  'print -r -- "$_dot" | command awk -F "\t" '\''$1=="./subdir" && $3=="./subdir" {found=1} END{exit !found}'\'''
lastw="$_fx/note.txt"
__fzf_tab_path_token_dir_base
assert_ok 'path token splits directory and base' \
  '[[ "$dir" == "'"$_fx"'" && "$base" == note.txt ]]'
lastw="$_fx/"
__fzf_tab_path_token_dir_base
assert_ok 'directory token has an empty base' \
  '[[ "$dir" == "'"$_fx"'/" || "$dir" == "'"$_fx"'" ]] && [[ -z "$base" ]]'
lastw=''
__fzf_tab_path_token_dir_base
assert_ok 'empty token lists the cwd' '[[ "$dir" == . && -z "$base" ]]'

_rb=$(mktemp -d "${TMPDIR:-/tmp}/rtfm-rb.XXXXXX")
LBUFFER='cp src/'
lastw='src/'
prefix_rest='cp'
( cd "$_fx" && __fzf_rtfm_tab_continue_rebuild "$_rb" all 'cp > ' )
assert_ok 'cp src/ hides man options' \
  '[[ -z "$(command tr -d "[:space:]" <"$_rb/man_rows")" ]]'
assert_ok 'cp src/ still lists the file inside' \
  'command awk -F "\t" '\''$1=="file" && $2=="f" {found=1} END{exit !found}'\'' "$_rb/file_rows"'
command rm -rf "$_rb"

# --- zoom, preview, and hidden toggle ---
_st=$(mktemp "${TMPDIR:-/tmp}/rtfm-st.XXXXXX")
_man=$(mktemp "${TMPDIR:-/tmp}/rtfm-mn.XXXXXX")
_tr=$(mktemp "${TMPDIR:-/tmp}/rtfm-tr.XXXXXX")
_tg=$(mktemp "${TMPDIR:-/tmp}/rtfm-tg.XXXXXX")
_ls=$(mktemp "${TMPDIR:-/tmp}/rtfm-ls.XXXXXX")
_pout=$(mktemp "${TMPDIR:-/tmp}/rtfm-pout.XXXXXX")
_focus=$(mktemp "${TMPDIR:-/tmp}/rtfm-focus.XXXXXX")
{
  print -r -- "$_fx"
  print -r -- 1
  print -r -- 1
  print -r -- 1
  print -r -- all
} >"$_st"
print -r -- $'build\tm\tcompile the project\nstatus\tm\tshow status' >"$_man"
__fzf_rtfm_write_transformer "$_tr" "$_st" "$_ls" all
__fzf_rtfm_write_toggler "$_tg" "$_st" "$_ls"
__fzf_rtfm_write_focus_script "$_focus" "$_man" "$_pout" "$_st"
command chmod +x "$_tr" "$_tg" "$_focus"
_zoom="$(command sh "$_tr" build m)"
assert_ok 'Tab on a subcommand accepts it' '[[ "$_zoom" == accept ]]'
assert_ok 'Tab on a subcommand does not enter a same-named directory' \
  '[[ "$(command sed -n 1p "$_st")" == "'"$_fx"'" ]]'
_zoom="$(command sh "$_tr" "$_fx/note.txt" f)"
assert_ok 'Tab on a file accepts it' '[[ "$_zoom" == accept ]]'
_zoom="$(command sh "$_tr" "$_fx/empty" f)"
assert_ok 'Tab on an empty directory accepts it' '[[ "$_zoom" == accept ]]'
_zoom="$(command sh "$_tr" "$_fx/subdir" f)"
assert_ok 'Tab on a non-empty directory zooms' '[[ "$_zoom" == reload* ]]'
assert_ok 'zoom drops man rows' '[[ "$(command sed -n 4p "$_st")" == 0 ]]'
assert_ok 'zoom state is the directory' \
  '[[ "$(command sed -n 1p "$_st")" == "'"$_fx"'/subdir" ]]'
assert_ok 'Tab lock walks the subtree' \
  '[[ "$(command sed -n 3p "$_st")" == "$__fzf_rtfm_tree_depth" ]]'
{
  print -r -- "$_fx"
  print -r -- 1
  print -r -- 1
  print -r -- 1
  print -r -- all
} >"$_st"
_tog="$(command sh "$_tg")"
assert_ok 'Alt-. reloads the list' '[[ "$_tog" == reload* ]]'
assert_ok 'Alt-. flips hidden off' '[[ "$(command sed -n 2p "$_st")" == 0 ]]'
command sh "$_focus" build m
_focus_out="$(command cat -- "$_pout")"
assert_ok 'preview of a subcommand is its description' \
  '[[ "$_focus_out" == "compile the project" ]]'
assert_ok 'preview of a subcommand is not the file' \
  '[[ "$_focus_out" != *built* ]]'
command sh "$_focus" "$_fx/note.txt" f
_focus_out="$(command cat -- "$_pout")"
assert_ok 'preview of a file is ls output' \
  '[[ "$_focus_out" == *note.txt* ]]'
_descf=$(mktemp "${TMPDIR:-/tmp}/rtfm-desc.XXXXXX")
print -r -- $'build\tm\tcompile the project' >"$_descf"
_prev="$("$__fzf_rtfm_preview_script" build m "$_descf")"
assert_ok 'preview script uses the description for kind m' \
  '[[ "$_prev" == "compile the project" ]]'
command rm -f "$_descf"

# --- help and key contracts ---
_help="$(__fzf_rtfm_print_help)"
assert_ok 'help says Enter does not run the command' \
  '[[ "$_help" == *"does not run the command"* ]]'
assert_ok 'help says a path command finishes a directory argument' \
  '[[ "$_help" == *"cp src dst"* ]]'
assert_ok 'help says cd and pushd leave the slash open' \
  '[[ "$_help" == *"cd and pushd leave the slash"* ]]'
assert_ok 'help says spaces are escaped' \
  '[[ "$_help" == *"my\\ dir/"* ]]'
assert_ok 'mixed picker Tab is not a plain accept' \
  '[[ "${__fzf_rtfm_fzf_binds_preview_nav[*]}" != *tab:accept* ]]'
assert_ok 'Esc aborts the picker' \
  '[[ "${__fzf_rtfm_fzf_binds_preview_nav[*]}" == *esc:abort* ]]'
assert_ok 'picker binds do not run the command line' \
  '[[ "${__fzf_rtfm_fzf_binds_basic[*]}" != *enter:execute* && "${__fzf_rtfm_fzf_binds_basic[*]}" != *tab:execute* && "${__fzf_rtfm_fzf_binds_preview_nav[*]}" != *enter:execute* && "${__fzf_rtfm_fzf_binds_preview_nav[*]}" != *tab:execute* ]]'
if command fzf --help 2>/dev/null | command rg -q -- '--with-shell'; then
  assert_ok 'fzf children use the POSIX shell' \
    '[[ "${__fzf_rtfm_with_shell[*]}" == */bin/sh\ -c* ]]'
fi
if functions __fzf_pick_mixed | command rg -F -q -- '[ "$kind" = m ] || continue'; then
  print -r -- "ok  - ctrl-f search skips non-option rows"
  PASS=$((PASS + 1))
else
  print -r -- "FAIL- ctrl-f search skips non-option rows"
  FAIL=$((FAIL + 1))
fi
_sqset="$(__fzf_rtfm_sh_set name "a'b")"
if [[ "$_sqset" == "name='a'\\''b'" ]]; then
  print -r -- "ok  - sh assignment quotes an apostrophe"
  PASS=$((PASS + 1))
else
  print -r -- "FAIL- sh assignment quotes an apostrophe (got $_sqset)"
  FAIL=$((FAIL + 1))
fi

if man -k '^git-' >/dev/null 2>&1; then
  _gitsubs="$(__fzf_parse_man_subcommands git 2>/dev/null)" || _gitsubs=""
  assert_ok 'git man subcommands include status' \
    '[[ "$_gitsubs" == *status* ]]'
else
  print -r -- "skip- git man -k subcommands"
fi

command rm -rf -- "$_fx"
command rm -f "$_st" "$_man" "$_tr" "$_tg" "$_ls" "$_pout" "$_focus"

# --- commands, subcommands, arguments, options, paths, wrappers ---
assert_ok 'wrappers: the eight wrappers are recognized' \
  '__fzf_rtfm_is_wrapper sudo && __fzf_rtfm_is_wrapper doas && __fzf_rtfm_is_wrapper command && __fzf_rtfm_is_wrapper builtin && __fzf_rtfm_is_wrapper env && __fzf_rtfm_is_wrapper time && __fzf_rtfm_is_wrapper nice && __fzf_rtfm_is_wrapper nohup'
assert_ok 'wrappers: a real command is not a wrapper' \
  '! __fzf_rtfm_is_wrapper git && ! __fzf_rtfm_is_wrapper cp && ! __fzf_rtfm_is_wrapper ls'
LBUFFER='sudo git'
assert_ok 'commands: sudo git is still the command name' '__fzf_tab_completing_command_name'
LBUFFER='sudo git '
assert_ok 'commands: sudo git plus space is past the command' '! __fzf_tab_completing_command_name'
prefix_rest=''
lastw=''
__fzf_apply_pick 'nosuchcmd'
assert_ok 'commands: a command is inserted as one word plus a space' \
  '[[ "$LBUFFER" == "nosuchcmd " ]]'
_ec=0
_out="$(__fzf_build_entries rtfm-no-such-cmd-xyz '' 2>/dev/null)" || _ec=$?
assert_ok 'commands: an unknown command fails' '[[ $_ec -ne 0 && -z "$_out" ]]'
if __fzf_man_topic_exists ls; then
  _lsroot="$(__fzf_build_entries ls '' 2>/dev/null)" || _lsroot=""
  assert_ok 'commands: ls offers options' \
    '[[ "$_lsroot" == *"-l"* || "$_lsroot" == *"--all"* || "$_lsroot" == *"-a"* ]]'
else
  print -r -- "skip- ls man page"
fi

LBUFFER='git status README'
assert_ok 'subcommands: a later argument does not replace the subcommand' \
  '[[ "$(__fzf_get_cmd_and_sub)" == git$'\''\t'\''status ]]'
LBUFFER='git -- status'
assert_ok 'subcommands: -- does not hide the subcommand' \
  '[[ "$(__fzf_get_cmd_and_sub)" == git$'\''\t'\''status ]]'
LBUFFER='sudo -u root git status'
assert_ok 'subcommands: a wrapper still sees the subcommand' \
  '[[ "$(__fzf_get_cmd_and_sub)" == git$'\''\t'\''status ]]'
prefix_rest='git'
lastw=''
__fzf_apply_pick 'status'
assert_ok 'subcommands: a subcommand is inserted literally' \
  '[[ "$LBUFFER" == "git status " ]]'
assert_ok 'subcommands: a path is not a finished subcommand' \
  '! __fzf_rtfm_sub_token_complete cp src src "cp src"'
if __fzf_man_topic_exists git && __fzf_man_topic_exists git-status; then
  _gitroot="$(__fzf_build_entries git '' 2>/dev/null)" || _gitroot=""
  assert_ok 'subcommands: git offers status' \
    '[[ "$_gitroot" == status$'\''\t'\''* || "$_gitroot" == *$'\''\n'\''status$'\''\t'\''* ]]'
  _gitst="$(__fzf_build_entries git status 2>/dev/null)" || _gitst=""
  assert_ok 'options: git status offers options' \
    '[[ "$_gitst" == *"--"* ]]'
else
  print -r -- "skip- git status man page"
fi

LBUFFER='ls -l'
__fzf_zle_token_state
assert_ok 'options: a flag is not the subcommand' \
  '[[ "$(__fzf_get_cmd_and_sub)" == ls$'\''\t'\'' ]]'
assert_ok 'options: a flag is not a path' \
  '[[ "$lastw" == "-l" ]] && ! __fzf_rtfm_path_only'
LBUFFER='git status --short'
assert_ok 'options: a flag after a subcommand leaves the subcommand' \
  '[[ "$(__fzf_get_cmd_and_sub)" == git$'\''\t'\''status ]]'
LBUFFER='git commit -m msg'
assert_ok 'arguments: a message is not the subcommand' \
  '[[ "$(__fzf_get_cmd_and_sub)" == git$'\''\t'\''commit ]]'
LBUFFER='cp src dest'
assert_ok 'arguments: the first path is kept and the second does not replace it' \
  '[[ "$(__fzf_get_cmd_and_sub)" == cp$'\''\t'\''src ]]'
LBUFFER='cp src dest '
__fzf_zle_token_state
assert_ok 'arguments: a finished path leaves the next slot empty' \
  '[[ -z "$lastw" ]] && ! __fzf_rtfm_path_only && ! __fzf_tab_completing_command_name'
_optrows=$'--all\tm\tall\n-l\tm\tlong'
_optout="$(print -r -- "$_optrows" | __fzf_rtfm_filter_used_line_tokens 'ls --all src/')"
assert_ok 'options: a used option stays hidden beside a path' \
  '[[ "$_optout" != *"--all"* ]]'
assert_ok 'options: an unused option stays beside a path' \
  'print -r -- "$_optout" | command awk -F "\t" '\''$1=="-l"{found=1} END{exit !found}'\'''

LBUFFER='cp my\ dir/'
__fzf_zle_token_state
assert_ok 'paths: an escaped directory is still the argument' \
  '[[ "$(__fzf_get_cmd_and_sub)" == cp$'\''\tmy dir/'\'' ]]'
assert_ok 'paths: an escaped directory is a directory prefix' \
  '__fzf_rtfm_is_dir_prefix && __fzf_rtfm_path_only'
LBUFFER='cp /tmp/file'
__fzf_zle_token_state
assert_ok 'paths: an absolute path is path-only' \
  '__fzf_last_word_is_pathlike "$lastw" && __fzf_rtfm_path_only'
assert_ok 'paths: an absolute path does not replace the command' \
  '[[ "$(__fzf_get_cmd_and_sub)" == cp$'\''\t'\''/tmp/file ]]'

LBUFFER='doas git status'
assert_ok 'wrappers: doas sees the real command and subcommand' \
  '[[ "$(__fzf_get_cmd_and_sub)" == git$'\''\t'\''status ]]'
LBUFFER='env -u PATH ls'
assert_ok 'wrappers: env -u sees ls' \
  '[[ "$(__fzf_get_cmd_and_sub)" == ls$'\''\t'\'' ]]'
LBUFFER='nice -10 make'
assert_ok 'wrappers: nice -10 sees make' \
  '[[ "$(__fzf_get_cmd_and_sub)" == make$'\''\t'\'' ]]'
LBUFFER='command -- ls'
assert_ok 'wrappers: command -- sees ls' \
  '[[ "$(__fzf_get_cmd_and_sub)" == ls$'\''\t'\'' ]]'
LBUFFER='sudo command ls -l'
assert_ok 'wrappers: stacked wrappers see ls' \
  '[[ "$(__fzf_get_cmd_and_sub)" == ls$'\''\t'\'' ]]'
LBUFFER='sudo -u root git status --short src/'
__fzf_zle_token_state
assert_ok 'wrappers: one line keeps command, subcommand, option, and path' \
  '[[ "$(__fzf_get_cmd_and_sub)" == git$'\''\t'\''status && "$lastw" == "src/" ]] && __fzf_rtfm_path_only && ! __fzf_tab_completing_command_name'

# --- cp: bare names start at cwd; slash locks; Tab locks a subdirectory ---
assert_ok 'paths: a bare name is not an explicit path' \
  '! __fzf_rtfm_path_is_explicit src'
assert_ok 'paths: a slash path is explicit' \
  '__fzf_rtfm_path_is_explicit src/'
assert_ok 'paths: a tilde path is explicit' \
  '__fzf_rtfm_path_is_explicit "~/src"'
_keep="$(print -r -- $'src\tf\tsrc\nnote\tf\tnote' | __fzf_rtfm_filter_used_line_tokens 'cp src')"
assert_ok 'paths: the path being typed stays selectable' \
  'print -r -- "$_keep" | command awk -F "\t" '\''$1=="src"{found=1} END{exit !found}'\'''
_done="$(print -r -- $'src\tf\tsrc\nnote\tf\tnote' | __fzf_rtfm_filter_used_line_tokens 'cp src ')"
assert_ok 'paths: a finished path is not offered again' \
  '! print -r -- "$_done" | command awk -F "\t" '\''$1=="src"{found=1} END{exit !found}'\'''

_tree=$(mktemp -d "${TMPDIR:-/tmp}/rtfm-tree.XXXXXX")
mkdir -p "$_tree/work/src/nested" "$_tree/out"
print -r -- x >"$_tree/work/note"
print -r -- x >"$_tree/work/src/nested/deep"
LBUFFER='cp src'
lastw='src'
prefix_rest='cp'
( cd "$_tree/work" && __fzf_rtfm_tab_continue_rebuild "$_tree/out" all 'cp > ' )
assert_ok 'cp bare directory name starts at the cwd' \
  '[[ "$(command cat -- "$_tree/out/list_dir")" == . ]]'
assert_ok 'cp bare name still lists a sibling file' \
  'command awk -F "\t" '\''$1=="note" && $2=="f" {found=1} END{exit !found}'\'' "$_tree/out/file_rows"'
assert_ok 'cp bare name fuzzy-matches nested files' \
  'command awk -F "\t" '\''$1=="src/nested/deep" {found=1} END{exit !found}'\'' "$_tree/out/file_rows"'
command rm -rf "$_tree/out"
mkdir -p "$_tree/out"
LBUFFER='cp src/'
lastw='src/'
prefix_rest='cp'
( cd "$_tree/work" && __fzf_rtfm_tab_continue_rebuild "$_tree/out" all 'cp > ' )
assert_ok 'cp src/ locks that directory' \
  '[[ "$(command cat -- "$_tree/out/list_dir")" == src || "$(command cat -- "$_tree/out/list_dir")" == src/ ]]'
assert_ok 'cp src/ fuzzy-matches inside its subdirectories' \
  'command awk -F "\t" '\''$1=="nested/deep" {found=1} END{exit !found}'\'' "$_tree/out/file_rows"'
mkdir -p "$_tree/work/src/nested/inner"
print -r -- x >"$_tree/work/src/file"
command rm -rf "$_tree/out"
mkdir -p "$_tree/out"
LBUFFER='cd src'
lastw='src'
prefix_rest='cd'
( cd "$_tree/work" && __fzf_rtfm_tab_continue_rebuild "$_tree/out" dirs 'cd > ' )
assert_ok 'cd bare directory name starts at the cwd' \
  '[[ "$(command cat -- "$_tree/out/list_dir")" == . ]]'
assert_ok 'cd bare name lists directories only' \
  'command awk -F "\t" '\''$1=="src"{found=1} END{exit !found}'\'' "$_tree/out/file_rows" && ! command awk -F "\t" '\''$1=="note"{found=1} END{exit !found}'\'' "$_tree/out/file_rows"'
assert_ok 'cd bare name fuzzy-matches nested directories' \
  'command awk -F "\t" '\''$1=="src/nested/inner"{found=1} END{exit !found}'\'' "$_tree/out/file_rows"'
command rm -rf "$_tree/out"
mkdir -p "$_tree/out"
LBUFFER='cd src/'
lastw='src/'
prefix_rest='cd'
( cd "$_tree/work" && __fzf_rtfm_tab_continue_rebuild "$_tree/out" dirs 'cd > ' )
assert_ok 'cd src/ locks that directory' \
  '[[ "$(command cat -- "$_tree/out/list_dir")" == src || "$(command cat -- "$_tree/out/list_dir")" == src/ ]]'
assert_ok 'cd src/ fuzzy-matches nested directories' \
  'command awk -F "\t" '\''$1=="nested/inner"{found=1} END{exit !found}'\'' "$_tree/out/file_rows"'
assert_ok 'cd src/ does not list files' \
  '! command awk -F "\t" '\''$1=="file"{found=1} END{exit !found}'\'' "$_tree/out/file_rows"'
command rm -rf "$_tree"

print -r -- ""
print -r -- "passed=$PASS failed=$FAIL"
(( FAIL == 0 ))
