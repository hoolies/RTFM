#!/usr/bin/env zsh
# Reproduce man-text dump from fzf preview under SHELL=zsh.
emulate -L zsh
zle() { :; }
bindkey() { :; }
builtin source "${0:A:h:h}/fzf-man-opts.zsh"

print -r -- "with_shell=${(j: :)__fzf_rtfm_with_shell}"
print -r -- "SHELL=$SHELL"

LBUFFER='ls --author '
entries="$(__fzf_build_entries ls '' "$LBUFFER" 2>/dev/null)" || entries=""
man_rows="$(__fzf_rtfm_entries_to_man_rows "$entries" "$LBUFFER")"
ps="$__fzf_rtfm_preview_script"
manfile="$(mktemp "${TMPDIR:-/tmp}/rtfm-man.XXXXXX")"
print -r -- "$man_rows" >"$manfile"

color_line="$(print -r -- "$man_rows" | awk -F '\t' '$1 ~ /color/ { print; exit }')"
tok="${color_line%%$'\t'*}"
print -r -- "tok=$tok"

run_fzf_preview() {
  local label="$1"
  shift
  print -r -- "=== $label ==="
  : > /tmp/rtfm-fzf-err
  # fzf needs a tty for preview; without one it may skip preview.
  # Drive preview manually the way fzf/with-shell would.
  "$@" 2>/tmp/rtfm-fzf-err
  print -r -- "stderr_bytes=$(wc -c < /tmp/rtfm-fzf-err)"
  if [[ -s /tmp/rtfm-fzf-err ]]; then
    head -c 700 /tmp/rtfm-fzf-err
    print -r -- ""
  fi
}

# 1) Current safe preview under /bin/sh -c
run_fzf_preview 'sh -c safe preview' \
  /bin/sh -c "$ps \"\$1\" \"\$2\" \"\$3\"" _ "$tok" m "$manfile"

# 2) zsh -c safe preview (what SHELL=zsh does even with {1}{2} manfile)
run_fzf_preview 'zsh -c safe preview' \
  zsh -c "$ps \"\$1\" \"\$2\" \"\$3\"" _ "$tok" m "$manfile"

# 3) Classic broken: zsh -c with full line as a single-quoted string that
#    contains apostrophes from a LONG man excerpt (docs path).
long="$(__fzf_rtfm_man_text ls 2>/dev/null | command awk '
  /TIME_STYLE|always|EXIT STATUS/ { keep=1 }
  keep { print }
  /EXIT STATUS/ { c++; if (c>=8) exit }
')"
print -r -- "=== long excerpt bytes=${#long} ==="
# Broken embedding: wrap long in single quotes (how a naive preview breaks)
run_fzf_preview 'zsh -c broken single-quoted man excerpt' \
  zsh -c "printf '%s\n' '$long'"

# 4) What if preview is still "$ps {}" and {} is expanded by fzf into the
#    command string with only outer double quotes?
run_fzf_preview 'zsh -c old {} style with short row' \
  zsh -c "$ps $color_line"

# 5) Confirm whether interactive widget path still calls docs_text
typeset -g _RTFM_DOCS_CALLS=0
functions -c __fzf_rtfm_docs_text __fzf_rtfm_docs_text_orig
__fzf_rtfm_docs_text() {
  _RTFM_DOCS_CALLS=$((_RTFM_DOCS_CALLS + 1))
  __fzf_rtfm_docs_text_orig "$@"
}
__fzf_rtfm_cmd_wants_files ls '' "$entries" && print -r -- "wants_files=yes"
print -r -- "docs_calls_after_wants=${_RTFM_DOCS_CALLS}"

command rm -f "$manfile"
