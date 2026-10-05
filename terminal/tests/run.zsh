#!/usr/bin/env zsh
# vozlocal test suite. Run: zsh terminal/tests/run.zsh
emulate -L zsh
setopt extended_glob

unset VOZLOCAL_REGION VOZLOCAL_DELAY VOZLOCAL_INTERVAL VOZLOCAL_SYNC_INTERVAL VOZLOCAL_BOT_URL VOZLOCAL_BOT_TOKEN VOZLOCAL_NOTIFY NO_COLOR  # user settings must not leak into the tests

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

lit() { print -rn -- ${(b)1} }  # a check pattern that matches $1 exactly

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

check "voz colours the phrase bold bright cyan and the countdown grey, as in the demo" \
  "${$(run 'VOZLOCAL_DELAY=1; voz')//$'\e'/<E>}" \
  "$(lit '<E>[1;38;5;81mhola<E>[0m')*$(lit '<E>[38;5;242m....<E>[0m')*$(lit '→ hello')"

check "NO_COLOR turns the colours off, and still shows the phrase, dots and meaning" \
  "${$(run 'VOZLOCAL_DELAY=1; NO_COLOR=1; voz')//$'\e'/<E>}" "hola*....*→ hello~*<E>\\[[0-9;]#m*"

check "Ctrl-C mid-countdown clears the line and returns 130" \
  "$(run_tty "$SETUP; VOZLOCAL_DELAY=5; (sleep 1; kill -INT \$\$) & voz; print rc=\$?")" "*rc=130*"

# Phrase lines (the bold first line of each voz) from n calls in a row, one per element.
# voz runs directly, not in a pipeline: a subshell per call would give every call the same $RANDOM.
voz_lines() { print -l ${(M)${(f)"$(run "XDG_CACHE_HOME=${(q)TMP}/norepeat $1; repeat $2 voz")"}:#*\[1;38;5;81m*} }
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
  "$(run "XDG_CACHE_HOME=${(q)TMP}/norepeat; out=\$(voz 2>&1); rc=\$?; [[ \$out == *'is a directory'* ]] && print ERR; print rc=\$rc")" "rc=0"
check "yas with a directory where last_phrase should be fails with a message" \
  "$(run "XDG_CACHE_HOME=${(q)TMP}/norepeat; yas; print rc=\$?")" $'yas: no phrase to mark yet, run voz first\nrc=1'

# Opening a FIFO blocks until its other end is opened. After 5s the watchdog marks the run as hung and keeps
# opening every FIFO read-write until it's stopped. That frees whatever is blocked on either end, even an orphaned
# child, so a regression fails instead of hanging the suite.
fifo_run() {  # fifo_run <cache dir> <command>
  local d=$1/vozlocal out
  { sleep 5; : > $1/hung; while :; do for f in $d/*(Np); do : <>$f; done; sleep 0.2; done } >/dev/null 2>&1 &!
  local watchdog=$!
  out=$(run "XDG_CACHE_HOME=${(q)1}; $2")
  kill $watchdog 2>/dev/null
  [[ -e $1/hung ]] && out+=$'\nHUNG'
  print -r -- $out
}

F=$TMP/fifo
rm -rf $F; mkdir -p $F/vozlocal; mkfifo $F/vozlocal/{last_phrase,learned}
check "a FIFO where last_phrase and learned should be doesn't hang voz or yas" \
  "$(fifo_run $F 'voz >/dev/null; print voz=$?; yas; print yas=$?')" \
  $'voz=0\nyas: no phrase to mark yet, run voz first\nyas=1'

rm -rf $F; mkdir -p $F/vozlocal; mkfifo $F/vozlocal/learned
check "yas with a FIFO where learned should be fails instead of hanging" \
  "$(fifo_run $F 'voz >/dev/null; print voz=$?; yas; print yas=$?')" \
  $'voz=0\nyas: */learned isn\'t a regular file\nyas=1'

rm -rf $F; mkdir -p $F/vozlocal/learned
check "yas with a directory where learned should be fails with a message" \
  "$(run "XDG_CACHE_HOME=${(q)F}; voz >/dev/null; yas; print rc=\$?")" \
  $'yas: */learned isn\'t a regular file\nrc=1'
rm -rf $F

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
reset_sync() { rm -rf $TMP/sync $MINE $TMP/curl.*(N) $TMP/reply $TMP/osascript.args }
# osascript stand-in, so tests never post real notifications: records each argument on its own line.
N="osascript() { print -rl -- \"\$@\" '--' >> \$VOZLOCAL_HOME/osascript.args }"
S="$S; $N"

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

reset_sync; print "1|Bondi|Bus" > $TMP/reply
check "a sync with no terminal watching posts a notification of the new phrase" \
  "$(run "$S; voz sync" >/dev/null; grep -v '^-e$' $TMP/osascript.args | sed -n '4,5p')" "$(lit $'New phrase from WhatsApp\nBondi → Bus')"

reset_sync; print "1|Bondi|Bus\n2|Che|Hey\n3|Fiaca|Laziness\n4|Guita|Money" > $TMP/reply
check "several new phrases are named in one notification, at most three" \
  "$(run "$S; voz sync" >/dev/null; grep -v '^-e$' $TMP/osascript.args | sed -n '4,5p')" "$(lit $'4 new phrases from WhatsApp\nBondi, Che, Fiaca, …')"

reset_sync; print -n > $TMP/reply
check "no notification when nothing is new" "$(run "$S; voz sync" >/dev/null; ls $TMP/osascript.args 2>&1)" "*No such file*"

reset_sync; print "1|Bondi|Bus" > $TMP/reply
check "VOZLOCAL_NOTIFY=0 turns notifications off" \
  "$(run "$S; VOZLOCAL_NOTIFY=0; voz sync" >/dev/null; ls $TMP/osascript.args 2>&1)" "*No such file*"

reset_sync; print "1|Bondi|Bus" > $TMP/reply
check "a voz sync typed in a terminal prints, and doesn't notify" \
  "$(run_tty "$SETUP; $S; voz sync" | tr -d '\r'; ls $TMP/osascript.args 2>&1)" "*voz sync: 1 new phrase*No such file*"

reset_sync; print '1|-e do shell script "touch '$TMP'/pwned"|"quoted" \\ back' > $TMP/reply
check "a phrase reaches osascript as text, not script" \
  "$(run "$S; voz sync" >/dev/null; grep -v '^-e$' $TMP/osascript.args | sed -n '5p'; ls $TMP/pwned 2>&1)" \
  "$(lit '-e do shell script "touch '$TMP'/pwned" → "quoted" \ back')*No such file*"

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

# --- Chrome host (vozlocal-host) ---

H=$TMP/host
hex() { print -rn -- $1 | od -An -v -tx1 | tr -d ' \n' }
# Frame a message the way Chrome does: its length in 4 bytes, then the message.
frame() { local n=${#1}; printf "\\x$(( [##16] n & 255 ))\\x$(( [##16] n >> 8 & 255 ))\\x00\\x00%s" $1 }
# Send one message to the host. Prints the reply without its 4-byte length.
host() { frame $1 | XDG_CACHE_HOME=$H/cache VOZLOCAL_HOME=$H/home $ROOT/vozlocal-host | tail -c +5 }
host_reset() {
  rm -rf $H; mkdir -p $H/cache/vozlocal $H/home/data/es_AR
  print "phrase|translation\nBondi|Bus\nno separator" > $H/home/data/es_AR/mine.psv
  print "Che|Hey" > $H/cache/vozlocal/learned
}
learn() { host "{\"op\":\"learn\",\"region\":\"es_AR\",\"key\":\"$(hex $1)\",\"on\":$2}" }
STATE='{"op":"state","region":"es_AR"}'

host_reset
check "the host sends learned phrases and mine.psv as hex" \
  "$(host $STATE)" "$(lit "{\"ok\":true,\"learned\":[\"$(hex 'Che|Hey')\"],\"mine\":[\"$(hex 'Bondi|Bus')\"]}")"

check "the host's reply starts with its length" \
  "$(frame $STATE | XDG_CACHE_HOME=$H/cache VOZLOCAL_HOME=$H/home $ROOT/vozlocal-host \
     | head -c 4 | od -An -tu4 | tr -d ' ')" "$(( ${#$(host $STATE)} ))"

learn 'Bondi|Bus' true >/dev/null; learn 'Bondi|Bus' true >/dev/null
check "learning through the host adds a phrase once" "$(<$H/cache/vozlocal/learned)" "$(lit $'Che|Hey\nBondi|Bus')"

learn 'Che|Hey' false >/dev/null; learn 'Nope|x' false >/dev/null
check "unlearning through the host removes only that phrase" "$(<$H/cache/vozlocal/learned)" "$(lit 'Bondi|Bus')"

learn 'Bondi|Bus' false >/dev/null
check "unlearning the last phrase leaves an empty file" \
  "$(host $STATE); size=$(wc -c < $H/cache/vozlocal/learned | tr -d ' ')" \
  "$(lit "{\"ok\":true,\"learned\":[],\"mine\":[\"$(hex 'Bondi|Bus')\"]}; size=0")"

check "a phrase with accents round-trips through the host" \
  "$(learn '¿Qué onda?|What'\''s up?' true)" "*\"$(hex '¿Qué onda?|What'\''s up?')\"*"

host_reset
check "the host refuses a bad region" "$(host '{"op":"state","region":"../x"}')" "$(lit '{"ok":false,"error":"bad region"}')"
check "the host refuses an unknown op" "$(host '{"op":"rm","region":"es_AR"}')" "$(lit '{"ok":false,"error":"bad op"}')"
check "the host refuses a key that isn't hex" \
  "$(host '{"op":"learn","region":"es_AR","key":"abc","on":true}')" "$(lit '{"ok":false,"error":"bad key"}')"
check "the host refuses a key without | or with a newline" \
  "$(learn 'no separator' true; learn $'a|b\nc|d' true)" "$(lit '{"ok":false,"error":"bad key"}{"ok":false,"error":"bad key"}')"
check "a refused change leaves learned alone" "$(<$H/cache/vozlocal/learned)" "$(lit 'Che|Hey')"
check "the host refuses a bad length" \
  "$(printf '\x00\x00\x00\x00' | XDG_CACHE_HOME=$H/cache VOZLOCAL_HOME=$H/home $ROOT/vozlocal-host | tail -c +5)" \
  "$(lit '{"ok":false,"error":"bad message length"}')"

rm -rf $H; mkdir -p $H/cache $H/home
check "with no files yet, the host sends empty lists" "$(host $STATE)" "$(lit '{"ok":true,"learned":[],"mine":[]}')"
check "the first phrase learned through the host creates learned" \
  "$(learn 'Che|Hey' true >/dev/null; cat $H/cache/vozlocal/learned)" "$(lit 'Che|Hey')"

host_reset; rm $H/cache/vozlocal/learned; mkfifo $H/cache/vozlocal/learned
check "a FIFO where learned should be doesn't hang the host" \
  "$(host $STATE; learn 'Bondi|Bus' true)" \
  "$(lit "{\"ok\":true,\"learned\":[],\"mine\":[\"$(hex 'Bondi|Bus')\"]}{\"ok\":false,\"error\":\"learned is not a regular file\"}")"

host_reset
check "the host refuses a key holding a control character" \
  "$(host '{"op":"learn","region":"es_AR","key":"00417c42","on":true}')" "$(lit '{"ok":false,"error":"bad key"}')"

host_reset; mkfifo $H/cache/vozlocal/learned.lock
check "a FIFO where learned.lock should be doesn't hang the host" \
  "$(learn 'Bondi|Bus' true)" "$(lit '{"ok":false,"error":"learned.lock is not a regular file"}')"

host_reset; mv $H/cache/vozlocal/learned $H/real-learned; ln -s $H/real-learned $H/cache/vozlocal/learned
learn 'Bondi|Bus' true >/dev/null; learn 'Che|Hey' false >/dev/null
check "a symlinked learned stays a symlink, and its target changes" \
  "$([[ -L $H/cache/vozlocal/learned ]] && print link); $(<$H/real-learned)" "$(lit 'link; Bondi|Bus')"

host_reset; print "phrase|translation\ngá|y" > $H/home/data/es_AR/mine.psv
check "a mine.psv line is sent only if it holds a real |" "$(host $STATE)" "*\"mine\":\\[\"$(hex 'gá|y')\"\\]*"
print "phrase|translation\ngá" > $H/home/data/es_AR/mine.psv
check "...and a line whose bytes merely contain 7c isn't" "$(host $STATE)" "*\"mine\":\\[\\]*"

host_reset; repeat 6000 print -r -- "$(printf 'x%.0s' {1..90})|y" >> $H/cache/vozlocal/learned
check "the host refuses to send more than Chrome takes" "$(host $STATE)" "$(lit '{"ok":false,"error":"too much to send"}')"

host_reset; print -r -- 'Bondi|Bus' >> $H/cache/vozlocal/learned
check "yas and the host share one learned file" \
  "$(run "XDG_CACHE_HOME=${(q)H}/cache; print -r -- 'Guita|Money' > \$XDG_CACHE_HOME/vozlocal/last_phrase; yas >/dev/null"; host $STATE)" \
  "*\"$(hex 'Guita|Money')\"*"

# --- voz install-chrome / install-cron ---

C=$TMP/chrome-hosts
check "install-chrome writes Chrome's host manifest" \
  "$(run "VOZLOCAL_CHROME_HOSTS=${(q)C}; voz install-chrome" && cat $C/com.vozlocal.host.json)" \
  "voz: Chrome now shares*\"name\": \"com.vozlocal.host\"*\"path\": \"$C/com.vozlocal.host\"*\"type\": \"stdio\"*\"chrome-extension://anijgjheokodkngpcmkigapfjieeeaff/\"*"

host_reset; ln -s $ROOT/vozlocal-host $H/home/vozlocal-host  # the launcher runs the host in VOZLOCAL_HOME
check "the launcher it writes runs the host with this shell's paths" \
  "$(run "VOZLOCAL_CHROME_HOSTS=${(q)C}; XDG_CACHE_HOME=${(q)H}/cache; VOZLOCAL_HOME=${(q)H}/home; voz install-chrome >/dev/null"
     frame $STATE | env -i HOME=/nonexistent $C/com.vozlocal.host | tail -c +5)" \
  "$(lit "{\"ok\":true,\"learned\":[\"$(hex 'Che|Hey')\"],\"mine\":[\"$(hex 'Bondi|Bus')\"]}")"

check "install-chrome --remove takes both files away" \
  "$(run "VOZLOCAL_CHROME_HOSTS=${(q)C}; voz install-chrome --remove"; ls -A $C)" "voz: Chrome no longer shares with the terminal"

# A stand-in crontab that keeps the table in a file, and says "no crontab" like the real one when there's none.
CRON="crontab() {
  case \$1 in
    -l) [[ -e ${(q)TMP}/crontab ]] && cat ${(q)TMP}/crontab || { print -u2 'crontab: no crontab for you'; return 1 } ;;
    -r) rm -f ${(q)TMP}/crontab ;;
    *) cat > ${(q)TMP}/crontab ;;
  esac
}"
CRONLOG=$TMP/cache/vozlocal/cron.log
print '0 9 * * * other job\n\n# a comment\n*/15 * * * * old line # vozlocal sync' > $TMP/crontab
check "install-cron replaces an older sync line and keeps other jobs, however often it runs" \
  "$(run "$CRON; voz install-cron; voz install-cron" >/dev/null; cat $TMP/crontab)" \
  "$(lit $'0 9 * * * other job\n\n# a comment\n*/2 * * * * /bin/zsh -ic \'voz sync\' >| '"$CRONLOG"$' 2>&1 # vozlocal sync')"

rm -f $TMP/crontab
check "install-cron starts a crontab when there's none" \
  "$(run "$CRON; voz install-cron" >/dev/null; grep -c "^\*/2 .* # vozlocal sync\$" $TMP/crontab; wc -l < $TMP/crontab | tr -d ' ')" $'1\n1'

print '0 9 * * * other job' > $TMP/crontab
check "install-cron leaves the table alone if it can't read it" \
  "$(run "$CRON; crontab() { [[ \$1 == -l ]] && { print -u2 'crontab: permission denied'; return 1 }; print -r -- WROTE > ${(q)TMP}/crontab }
          voz install-cron; print rc=\$?; voz install-cron --remove; print rc=\$?"; cat $TMP/crontab)" \
  "*couldn't read your crontab*permission denied*rc=1*couldn't read*rc=1*0 9 \\* \\* \\* other job"
print '0 9 * * * other job' > $TMP/crontab
check "install-cron --remove takes the line away" \
  "$(run "$CRON; voz install-cron --remove" >/dev/null; cat $TMP/crontab)" "$(lit '0 9 * * * other job')"
check "install-cron --remove on the only line clears the table" \
  "$(print -r -- '* * * * * x # vozlocal sync' > $TMP/crontab; run "$CRON; voz install-cron --remove" >/dev/null; ls $TMP/crontab 2>&1)" "*No such file*"

# --- data files ---

bad=()
for f in $ROOT/data/*/*.psv; do
  [[ $(head -1 $f) == "phrase|translation" ]] || bad+=("${f:t}: bad header")
  awk 'NR > 1 && NF && !/\|/ { exit 1 }' $f || bad+=("${f:t}: row without |")
done
check "shipped phrase files are well formed" "${(j:; :)bad}" ""

print -r -- $'\n'"$passed passed, $failed failed"
(( failed == 0 ))
