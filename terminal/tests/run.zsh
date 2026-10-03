#!/usr/bin/env zsh
# vozlocal test suite. Run: zsh terminal/tests/run.zsh
emulate -L zsh
setopt extended_glob

unset VOZLOCAL_REGION VOZLOCAL_DELAY VOZLOCAL_INTERVAL VOZLOCAL_SYNC_INTERVAL VOZLOCAL_BOT_URL VOZLOCAL_BOT_TOKEN  # user settings must not leak into the tests

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

# Phrase lines (the bold first line of each voz) from n calls in a row, one per element.
# voz runs directly, not in a pipeline: a subshell per call would give every call the same $RANDOM.
voz_lines() { print -l ${(M)${(f)"$(run "XDG_CACHE_HOME=${(q)TMP}/norepeat $1; repeat $2 voz")"}:#*\[1;36m*} }
no_repeats() {  # no_repeats <lines…>: "<count> repeats=<consecutive equal pairs>"
  integer i r=0; for (( i = 2; i <= $#; i++ )); [[ ${(P)i} == ${(P)$((i - 1))} ]] && (( ++r )); print "$# repeats=$r"
}

rm -rf $TMP/norepeat
check "voz never shows the same phrase twice in a row when there's another" \
  "$(no_repeats ${(f)"$(voz_lines VOZLOCAL_REGION=two 30)"})" "30 repeats=0"

mkdir -p $TMP/data/three && print "phrase|translation\nuno|one\ndos|two\ntres|three" > $TMP/data/three/three.psv
rm -rf $TMP/norepeat; mkdir -p $TMP/norepeat/vozlocal && print "uno|one" > $TMP/norepeat/vozlocal/learned
lines=( ${(f)"$(voz_lines VOZLOCAL_REGION=three 30)"} )
check "voz avoids both learned phrases and the last one" \
  "$(no_repeats $lines) uno=${#${(M)lines:#*uno*}}" "30 repeats=0 uno=0"

rm -rf $TMP/norepeat; mkdir -p $TMP/norepeat/vozlocal && print "uno|one\ndos|two" > $TMP/norepeat/vozlocal/learned
check "voz avoids the last phrase even when every phrase is learned" \
  "$(no_repeats ${(f)"$(voz_lines VOZLOCAL_REGION=two 30)"})" "30 repeats=0"

print "phrase|translation\nsiete|seven" > $TMP/data/two/mine.psv; rm -rf $TMP/norepeat
lines=( ${(f)"$(voz_lines VOZLOCAL_REGION=two 30)"} )
check "a mine.psv phrase counts as the last one too" \
  "$(no_repeats $lines) siete=$(( ${#${(M)lines:#*siete*}} > 0 ))" "30 repeats=0 siete=1"
rm -f $TMP/data/two/mine.psv; rm -rf $TMP/data/three

rm -rf $TMP/norepeat
check "voz still shows a category's only phrase every time" \
  "$(voz_lines VOZLOCAL_REGION=test 3)" $'*hola*\n*hola*\n*hola*~*\n*\n*\n*'

rm -rf $TMP/norepeat; mkdir -p $TMP/norepeat/vozlocal
print -rn -- "${(l:3000000::x:)}|y" > $TMP/norepeat/vozlocal/last_phrase
check "a huge last phrase doesn't break voz" "$(run "XDG_CACHE_HOME=${(q)TMP}/norepeat; voz; print rc=\$?")" "*→ hello*rc=0"

rm -rf $TMP/norepeat; mkdir -p $TMP/norepeat/vozlocal/last_phrase
check "a directory where last_phrase should be is ignored" \
  "$(run "XDG_CACHE_HOME=${(q)TMP}/norepeat; voz 2>&1 | grep -c 'is a directory'")" "0"
rm -rf $TMP/norepeat

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

# --- voz sync ---

# curl stand-in: records its arguments and stdin, answers with $TMP/reply, fails like curl -f without one.
S="curl() { cat >| \$VOZLOCAL_HOME/curl.stdin; print -r -- \"\$@\" >> \$VOZLOCAL_HOME/curl.args; [[ -r \$VOZLOCAL_HOME/reply ]] || return 22; cat \$VOZLOCAL_HOME/reply }"
S="$S; XDG_CACHE_HOME=${(q)TMP}/sync VOZLOCAL_BOT_URL=https://bot.test/ VOZLOCAL_BOT_TOKEN=tok-123"
MINE=$TMP/data/test/mine.psv
reset_sync() { rm -rf $TMP/sync $MINE $TMP/curl.*(N) $TMP/reply }

reset_sync
check "voz sync without settings fails with a message" \
  "$(run 'voz sync; print rc=$?')" $'voz sync: set VOZLOCAL_BOT_URL and VOZLOCAL_BOT_TOKEN first\nrc=1'

check "voz sync refuses a token that could escape curl's config" \
  "$(run "$S; VOZLOCAL_BOT_TOKEN='x\" -o /tmp/pwned'; voz sync; print rc=\$?")" "*may only hold*rc=1"

print "1|Bondi|Bus\n2|Che|Hey" > $TMP/reply
check "voz sync adds new phrases to mine.psv" \
  "$(run "$S; voz sync")"$'\n'"$(<$MINE)" $'voz sync: 2 new phrases\nphrase?translation\nBondi?Bus\nChe?Hey'

check "voz sync sends the token on stdin, not the command line" \
  "$(<$TMP/curl.stdin) / $(<$TMP/curl.args)" '*Authorization: Bearer tok-123* / *--url https://bot.test/phrases?since=0'

print -n > $TMP/reply
check "voz sync asks only for phrases after the last one" \
  "$(run "$S; voz sync"; tail -1 $TMP/curl.args)" $'voz sync: up to date\n*since=2'

reset_sync; print "1|hola|hi\n2|Chamuyo|Sweet talk" > $TMP/reply
check "voz sync skips phrases already in the region" \
  "$(run "$S; voz sync")"$'\n'"$(<$MINE)" $'voz sync: 1 new phrase\nphrase?translation\nChamuyo?Sweet talk'

reset_sync; print "x|a|b\n1|a|b|c\n2|esc"$'\e'"[31m|red\n3|ok|fine" > $TMP/reply
check "voz sync drops malformed and hostile rows" \
  "$(run "$S; voz sync"; cat $MINE $TMP/sync/vozlocal/sync_last_id)" $'voz sync: 1 new phrase\nphrase?translation\nok?fine\n3'

for loc in C en_US.UTF-8; do
  reset_sync; printf '1|ok|fine\n2|sí|yes\n3|c1\302\233x|x\n4|bidi\342\200\256x|x\n5|bom\357\273\277x|x\n6|zw\342\200\213x|x\n7|bad\377x|x\n8|shy\302\255x|x\n9|tag\363\240\201\201x|x\n10|alm\330\234x|x\n11|nul\001x|x\n' > $TMP/reply
  check "voz sync drops C1, bidi, zero-width and invalid UTF-8 rows ($loc)" \
    "$(run "$S; LC_ALL=$loc voz sync"; cat $MINE $TMP/sync/vozlocal/sync_last_id)" \
    $'voz sync: 2 new phrases\nphrase?translation\nok?fine\nsí?yes\n11'
done

reset_sync; print "1|Bondi|Bus" > $TMP/reply
check "voz sync works with mv, rm, mkdir and cat aliased" \
  "$(zsh -fc "alias mv='mv -i' rm='rm -i' mkdir='mkdir -v' cat='cat -n'; $SETUP; $S; voz sync; print '2|Che|Hey' >| \$VOZLOCAL_HOME/reply; voz sync </dev/null" 2>&1; command cat $MINE)" \
  $'voz sync: 1 new phrase\nvoz sync: 1 new phrase\nphrase?translation\nBondi?Bus\nChe?Hey'

# Nothing may run while aliases are off: a Ctrl-C there would leave them off for the whole session.
lines=( ${(f)"$(<$PLUGIN)"} )
check "the plugin restores aliases before running anything at load" \
  "${(j:/:)lines[-3,-1]}" "*'setopt' 'aliases'/*'unset' '_vozlocal_aliases'/_vozlocal_startup"

reset_sync; mkdir -p $TMP/sync/vozlocal; touch $TMP/sync/vozlocal/sync.in.123 $MINE.tmp.123; print -n > $TMP/reply
check "voz sync clears temp files left by a killed sync" \
  "$(run "$S; voz sync"; print $TMP/sync/vozlocal/sync.in.*(N) $MINE.tmp.*(N))" "voz sync: up to date"

check "sourcing the plugin leaves the user's aliases on" \
  "$(zsh -fc "alias ll='ls -l'; source ${(q)PLUGIN} >/dev/null; [[ -o aliases ]] && alias ll")" "ll='ls -l'"

reset_sync; print "1|Bondi|Bus" > $TMP/reply; mkdir -p $TMP/sync/vozlocal
zsh -fc "zmodload zsh/system; : >> $TMP/sync/vozlocal/sync.lock; zsystem flock $TMP/sync/vozlocal/sync.lock; sleep 2" &
sleep 0.5
check "a second voz sync waits its turn" "$(run "$S; voz sync; print rc=\$?")" $'voz sync: already running\nrc=1'
wait
check "a lock left by a finished sync doesn't block the next one" "$(run "$S; voz sync")" "voz sync: 1 new phrase"

reset_sync; mkdir -p $TMP/back\\slash
check "a backslash in XDG_CACHE_HOME doesn't break learned phrases" \
  "$(run "XDG_CACHE_HOME=${(q)TMP}/back\\\\slash; VOZLOCAL_REGION=two; voz >/dev/null; yas >/dev/null; l=\$(<\$XDG_CACHE_HOME/vozlocal/learned); [[ \$(repeat 20 voz) == *\${l%%|*}* ]] && print SHOWN || print OK")" "OK"
rm -rf $TMP/back\\slash

reset_sync; print "phrase|translation\nmine|kept" > $MINE
check "a failed sync leaves mine.psv and the last id alone" \
  "$(run "$S; voz sync; print rc=\$?"; cat $MINE; [[ -e $TMP/sync/vozlocal/sync_last_id ]] && print MOVED)" \
  $'voz sync: could not reach the bot\nrc=1\nphrase?translation\nmine?kept'

reset_sync; print "phrase|translation\ntres|three" > $TMP/data/two/mine.psv
shown=$(run 'VOZLOCAL_REGION=two; repeat 40 voz')
check "voz mixes mine.psv into today's category" "$shown" "*three*"
check "voz still shows the category's own phrases" "$shown" "*(one|two)*"
mkdir -p $TMP/data/onlymine && cp $TMP/data/two/mine.psv $TMP/data/onlymine/
check "mine.psv alone is not a category" \
  "$(run 'VOZLOCAL_REGION=onlymine voz; print rc=$?')" $'vozlocal: no .psv files found\nrc=1'
rm -rf $TMP/data/two/mine.psv $TMP/data/onlymine

# Terminal opening with the bot configured. Sourced from a copy in $TMP so VOZLOCAL_HOME is the fixtures.
cp $PLUGIN $TMP/auto.plugin.zsh
auto="$S; VOZLOCAL_REGION=test VOZLOCAL_DELAY=0; source ${(q)TMP}/auto.plugin.zsh; repeat 30 { [[ -e ${(q)TMP}/curl.args ]] && break; sleep 0.1 }; sleep 0.3"
reset_sync; print "1|Bondi|Bus" > $TMP/reply
check "opening a terminal syncs in the background" "$(run_tty $auto; cat $MINE)" "*Bondi?Bus*"
rm -f $TMP/curl.args
check "a second terminal within VOZLOCAL_SYNC_INTERVAL doesn't sync again" \
  "$(run_tty $auto; [[ -e $TMP/curl.args ]] && print SYNCED)" "*~*SYNCED*"
reset_sync
check "a failed background sync lets the next terminal retry" \
  "$(run_tty $auto; [[ -e $TMP/sync/vozlocal/last_synced ]] && print STAMPED)" "*~*STAMPED*"
reset_sync

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
