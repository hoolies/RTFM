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
