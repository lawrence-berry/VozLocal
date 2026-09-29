#!/usr/bin/env zsh
# vozlocal test suite. Run: zsh terminal/tests/run.zsh
emulate -L zsh
setopt extended_glob

unset VOZLOCAL_REGION VOZLOCAL_DELAY VOZLOCAL_INTERVAL  # user settings must not leak into the tests

ROOT=${0:A:h:h}
PLUGIN=$ROOT/vozlocal.plugin.zsh
TMP=$(mktemp -d)
trap 'rm -rf $TMP' EXIT
integer passed=0 failed=0

# Fixtures: a region with a header, blank line, malformed row and one real phrase; and one with no phrases.
mkdir -p $TMP/data/{test,empty,two}
print "phrase|translation\nuno|one\ndos|two" > $TMP/data/two/two.psv
print "phrase|translation\n\nno separator here\nhola|hello\n" > $TMP/data/test/one.psv
print "phrase|translation" > $TMP/data/empty/none.psv

# Fresh zsh with the plugin loaded against the fixtures, no delay.
SETUP="source ${(q)PLUGIN} >/dev/null; XDG_CACHE_HOME=${(q)TMP}/cache VOZLOCAL_HOME=${(q)TMP} VOZLOCAL_REGION=test VOZLOCAL_DELAY=0"
run() { zsh -fc "$SETUP; $1" 2>&1 }

# Interactive shell on a pseudo-terminal, as a real new tab would be.
run_tty() {
  local cmd="export XDG_CACHE_HOME=${(q)TMP}/cache; $1"
  if script --version >/dev/null 2>&1; then  # util-linux (Linux)
    script -qec "zsh -fic ${(q)cmd}" /dev/null </dev/null 2>&1
  else                                       # BSD (macOS)
    script -q /dev/null zsh -fic $cmd </dev/null 2>&1
  fi
}

check() {  # check <name> <output> <pattern>
  if [[ $2 == $~3 ]]; then
    (( ++passed )); print -r -- "ok     $1"
  else
    (( ++failed )); print -r -- "FAIL   $1"$'\n'"       got: ${(q+)2}"
  fi
}

# --- voz ---

check "shows phrase then translation" \
  "$(run 'voz; print rc=$?')" $'*hola*→ hello\nrc=0'

check "never shows the header or malformed lines" \
  "$(run 'repeat 20 voz')" "(*hola*→ hello[[:space:]]#)##"

check "missing region fails with a message" \
  "$(run 'VOZLOCAL_REGION=nope voz; print rc=$?')" $'vozlocal: no .psv files found\nrc=1'

check "category with no phrases fails with a message" \
  "$(run 'VOZLOCAL_REGION=empty voz; print rc=$?')" $'vozlocal: no phrases in none.psv\nrc=1'

check "invalid VOZLOCAL_DELAY is not evaluated" \
  "$(run 'VOZLOCAL_DELAY="path[\$(touch $VOZLOCAL_HOME/pwned)]" voz >/dev/null; print rc=$?; [[ -e $VOZLOCAL_HOME/pwned ]] && print PWNED')" \
  "rc=0"

check "works despite hostile user shell options" \
  "$(run 'setopt ksh_arrays nounset no_glob; voz; print rc=$?')" "*→ hello*rc=0"

check "countdown shows one dot per quarter second" \
  "$(run 'VOZLOCAL_DELAY=1 voz')" "*....*...*..*.*→ hello*"

check "Ctrl-C mid-countdown clears the line and returns 130" \
  "$(run_tty "$SETUP; VOZLOCAL_DELAY=5; (sleep 1; kill -INT \$\$) & voz; print rc=\$?")" "*rc=130*"

# --- yas ---

C="XDG_CACHE_HOME=${(q)TMP}/yas"
check "yas before any phrase fails with a message" \
  "$(run "$C yas; print rc=\$?")" $'yas: no phrase to mark yet, run voz first\nrc=1'

check "yas marks the last phrase as learned" \
  "$(run "$C; rm -rf \$XDG_CACHE_HOME; voz >/dev/null; yas; cat \$XDG_CACHE_HOME/vozlocal/learned")" \
  '*learned: hola*hola?hello'

check "yas twice records the phrase once" \
  "$(run "$C; rm -rf \$XDG_CACHE_HOME; voz >/dev/null; yas >/dev/null; yas >/dev/null; print \$(( \$(wc -l < \$XDG_CACHE_HOME/vozlocal/learned) ))")" "1"

check "voz skips learned phrases" \
  "$(run "$C; rm -rf \$XDG_CACHE_HOME; VOZLOCAL_REGION=two; voz >/dev/null; yas >/dev/null; l=\$(<\$XDG_CACHE_HOME/vozlocal/learned); [[ \$(repeat 20 voz) == *\${l%%|*}* ]] && print SHOWN || print OK")" "OK"

check "voz falls back to learned phrases when all are learned" \
  "$(run "$C; rm -rf \$XDG_CACHE_HOME; voz >/dev/null; yas >/dev/null; voz; print rc=\$?")" "*→ hello*rc=0"

# --- daily category rotation ---

check "each category shows exactly once per cycle" \
  "$(run 'for c in 0 1 2; print ${(on)$(for p in 0 1 2; _vozlocal_category 3 $(( c * 3 + p )))}')" \
  $'1 2 3\n1 2 3\n1 2 3'

picks=( ${(u)${(f)"$(repeat 3 run '_vozlocal_category 5 12345')"}} )
check "category is stable for the whole day" "$picks" "<->"

orders=( ${(u)${(f)"$(run 'for c in {0..9}; { for p in {0..4}; print -n $(_vozlocal_category 5 $(( c * 5 + p ))); print }')"}} )
check "order is reshuffled between cycles" "$orders" "* *"

# --- auto-show on shell start ---

load="VOZLOCAL_DELAY=0; source ${(q)PLUGIN}; print done"

check "non-interactive shells stay quiet" \
  "$(zsh -fc "export XDG_CACHE_HOME=${(q)TMP}/cache; $load")" "done"

rm -rf $TMP/cache
check "first terminal shows a phrase" "$(run_tty $load)" "*→*done*"
check "second terminal within the interval stays quiet" "$(run_tty $load)" "*done*~*→*"
check "VOZLOCAL_INTERVAL=0 shows in every terminal" "$(run_tty "VOZLOCAL_INTERVAL=0; $load")" "*→*done*"

print -r -- 'path[$(touch '$TMP'/pwned)]' > $TMP/cache/vozlocal/last_shown
check "corrupt timestamp is ignored, not evaluated" \
  "$(run_tty $load; [[ -e $TMP/pwned ]] && print PWNED)" "*→*done*~*PWNED*"

# --- data files ---

bad=()
for f in $ROOT/data/*/*.psv; do
  [[ $(head -1 $f) == "phrase|translation" ]] || bad+=("${f:t}: bad header")
  awk 'NR > 1 && NF && !/\|/ { exit 1 }' $f || bad+=("${f:t}: row without |")
done
check "shipped phrase files are well formed" "${(j:; :)bad}" ""

print -r -- $'\n'"$passed passed, $failed failed"
(( failed == 0 ))
