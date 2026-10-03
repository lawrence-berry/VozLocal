# vozlocal: show a Spanish phrase, pause, then reveal the translation. See README.md.

# Parse this file with aliases off. zsh expands aliases when a function is defined, so a user's
# `alias mv='mv -i'` would otherwise end up inside these functions. Restored at the end of the file,
# before anything runs, so a Ctrl-C while the plugin loads can't leave the user's aliases off.
'builtin' 'typeset' '-gi' '_vozlocal_aliases=0'
[[ -o aliases ]] && _vozlocal_aliases=1
'builtin' 'setopt' 'no_aliases'

VOZLOCAL_HOME=${${(%):-%x}:A:h}
zmodload zsh/datetime zsh/system

# REPLY = value of variable $1 if it's a whole number, else $2. Guards $(( )), which evaluates code.
_vozlocal_int() {
  emulate -L zsh
  [[ ${(P)1} == <-> ]] && REPLY=${(P)1} || REPLY=$2
}

# Category index (1..$1) for day $2: each shows once per $1-day cycle, in an order shuffled per cycle.
_vozlocal_category() {
  awk -v n=$1 -v cycle=$(( $2 / $1 )) -v pos=$(( $2 % $1 )) 'BEGIN {
    srand(cycle)
    for (i = 1; i <= n; i++) order[i] = i
    for (i = n; i > 1; i--) { j = int(rand() * i) + 1; t = order[i]; order[i] = order[j]; order[j] = t }
    print order[pos + 1]
  }'
}

voz() {
  emulate -L zsh
  [[ $1 == sync ]] && { _vozlocal_sync; return }
  local data=$VOZLOCAL_HOME/data/${VOZLOCAL_REGION:-es_AR}
  # mine.psv (phrases from the WhatsApp bot) isn't a category: it joins whichever category is on today.
  local -a files=( $data/*.psv(N) )
  files=( ${files:#*/mine.psv} )
  (( $#files )) || { print -u2 "vozlocal: no .psv files found"; return 1 }

  local dir=${XDG_CACHE_HOME:-$HOME/.cache}/vozlocal idx line
  local -a src
  idx=$(_vozlocal_category $#files $(( EPOCHSECONDS / 86400 )))
  src=( $files[idx] )
  [[ -r $data/mine.psv ]] && src+=( $data/mine.psv )
  [[ -r $dir/learned ]] && src=( $dir/learned $src )
  # Skip learned phrases (whole lines in $dir/learned), unless every phrase in the category is learned.
  # Read $RANDOM here, not inside $( ): subshells all see the same value, so repeated voz calls would repeat.
  local seed=$RANDOM
  # Paths go through ENVIRON: awk -v would treat a backslash in them as an escape.
  line=$(VOZ_LEARNED=$dir/learned awk -v seed=$seed '
    FILENAME == ENVIRON["VOZ_LEARNED"] { done[$0]; next }
    FNR > 1 && /\|/ { all[++n] = $0; if (!($0 in done)) todo[++m] = $0 }
    END { srand(seed); if (m) print todo[int(rand() * m) + 1]; else if (n) print all[int(rand() * n) + 1] }' $src)
  [[ -n $line ]] || { print -u2 "vozlocal: no phrases in $files[idx]:t"; return 1 }
  mkdir -p $dir && print -r -- $line >| $dir/last_phrase

  _vozlocal_int VOZLOCAL_DELAY 2
  trap 'printf "\r\e[K"; return 130' INT
  print -r -- $'\e[1;36m'${line%%|*}$'\e[0m'
  local -i t
  for (( t = REPLY * 4; t > 0; t-- )); do
    printf '\r\e[K  %s' ${(l:t::.:)}
    sleep 0.25
  done
  print -r -- $'\r\e[K  → '${line#*|}
}

# Mark the phrase voz showed last as learned, so voz stops picking it.
yas() {
  emulate -L zsh
  local dir=${XDG_CACHE_HOME:-$HOME/.cache}/vozlocal last
  local -a learned
  [[ -r $dir/last_phrase ]] && last=$(<$dir/last_phrase)
  [[ -n $last ]] || { print -u2 "yas: no phrase to mark yet, run voz first"; return 1 }
  [[ -r $dir/learned ]] && learned=( ${(f)"$(<$dir/learned)"} )
  [[ -n ${(M)learned:#"$last"} ]] || print -r -- $last >> $dir/learned
  print -r -- "  ✓ learned: ${last%%|*}"
}

# voz sync: append phrases confirmed in the WhatsApp bot since the last sync to mine.psv. See bot/README.md.
_vozlocal_sync() {
  emulate -L zsh
  [[ -n $VOZLOCAL_BOT_URL && -n $VOZLOCAL_BOT_TOKEN ]] || {
    print -u2 "voz sync: set VOZLOCAL_BOT_URL and VOZLOCAL_BOT_TOKEN first"; return 1 }
  # The token goes to curl on stdin, so it never shows in `ps`; this keeps it from breaking out of the quotes.
  [[ $VOZLOCAL_BOT_TOKEN != *[^A-Za-z0-9._-]* ]] || {
    print -u2 "voz sync: VOZLOCAL_BOT_TOKEN may only hold letters, digits, . _ and -"; return 1 }

  local dir=${XDG_CACHE_HOME:-$HOME/.cache}/vozlocal data=$VOZLOCAL_HOME/data/${VOZLOCAL_REGION:-es_AR}
  local mine=$data/mine.psv since=0 result lock
  mkdir -p $dir $data || return 1
  # One sync at a time. The kernel drops the lock when its holder exits, so a killed sync can't leave it stuck.
  : >> $dir/sync.lock && zsystem flock -t 0 -f lock $dir/sync.lock 2>/dev/null || { print -u2 "voz sync: already running"; return 1 }
  # Holding the lock, so any temp files left by a sync that was killed can go.
  rm -f $dir/sync.(in|new).<->(N) $mine.tmp.<->(N)
  local fetched=$dir/sync.in.$$ fresh=$dir/sync.new.$$ tmp=$mine.tmp.$$
  {
    [[ -r $dir/sync_last_id ]] && since=$(<$dir/sync_last_id)
    [[ $since == <-> ]] || since=0
    print -r -- "header = \"Authorization: Bearer $VOZLOCAL_BOT_TOKEN\"" \
      | curl -fsS --max-time 15 -K - --url "${VOZLOCAL_BOT_URL%/}/phrases?since=$since" >| $fetched \
      || { print -u2 "voz sync: could not reach the bot"; return 1 }

    # Rows are `id|phrase|translation`. Keep well-formed ones whose phrase isn't in the region yet. awk runs on
    # bytes (LC_ALL=C) so a malformed row can't make it fail, and drops rows holding control characters (C0, C1),
    # bidi or zero-width marks, or anything that isn't valid UTF-8, which would break voz's own awk later.
    local -a files=( $data/*.psv(N) )
    result=$(LC_ALL=C VOZ_IN=$fetched VOZ_OUT=$fresh awk -F'|' '
      BEGIN {
        utf8 = "^([\001-\177]|[\302-\337][\200-\277]|\340[\240-\277][\200-\277]|[\341-\354\356\357][\200-\277][\200-\277]|" \
               "\355[\200-\237][\200-\277]|\360[\220-\277][\200-\277][\200-\277]|[\361-\363][\200-\277][\200-\277][\200-\277]|" \
               "\364[\200-\217][\200-\277][\200-\277])*$"
      }
      FILENAME != ENVIRON["VOZ_IN"] { if (FNR > 1) have[$1]; next }
      /^[0-9]+\|/ && $1 + 0 > max { max = $1 + 0 }
      !/^[0-9]+\|[^|]+\|[^|]+$/ || $0 !~ utf8 { next }
      /[\001-\037\177]|\302[\200-\237\255]|\330\234|\342\200[\213-\217\250-\256]|\342\201[\240-\244\246-\251]|\357\273\277|\357\277[\271-\273]|\363\240[\200-\201]/ { next }
      !($2 in have) { have[$2]; print $2 "|" $3 > ENVIRON["VOZ_OUT"]; n++ }
      END { print max + 0, n + 0 }' $files $fetched) || return 1
    local -a r=( ${=result} )

    if (( r[2] )); then
      { [[ -r $mine ]] && cat $mine || print phrase\|translation; cat $fresh } >| $tmp && mv -f $tmp $mine || return 1
    fi
    (( r[1] > since )) && print $r[1] >| $dir/sync_last_id
    (( r[2] )) && print "voz sync: $r[2] new phrase$([[ $r[2] == 1 ]] || print s)" || print "voz sync: up to date"
  } always {
    rm -f $fetched $fresh $tmp
    zsystem flock -u $lock
  }
}

# In interactive terminals: sync with the WhatsApp bot in the background at most once per
# VOZLOCAL_SYNC_INTERVAL minutes, and show a phrase at most once per VOZLOCAL_INTERVAL (0 = every shell).
_vozlocal_startup() {
  emulate -L zsh
  [[ -o interactive && -t 1 ]] || return 0
  local dir=${XDG_CACHE_HOME:-$HOME/.cache}/vozlocal synced
  if [[ -n $VOZLOCAL_BOT_URL ]]; then
    [[ -r $dir/last_synced ]] && synced=$(<$dir/last_synced)
    [[ $synced == <-> ]] || synced=0
    _vozlocal_int VOZLOCAL_SYNC_INTERVAL 60
    if (( EPOCHSECONDS - synced >= REPLY * 60 )); then
      # Stamped up front so terminals opening together don't all sync; cleared on failure so the next one retries.
      mkdir -p $dir && print $EPOCHSECONDS >| $dir/last_synced
      { _vozlocal_sync || rm -f $dir/last_synced } >/dev/null 2>&1 &!
    fi
  fi

  local stamp=$dir/last_shown last
  [[ -r $stamp ]] && last=$(<$stamp)
  [[ $last == <-> ]] || last=0
  _vozlocal_int VOZLOCAL_INTERVAL 30
  (( REPLY && EPOCHSECONDS - last < REPLY * 60 )) && return
  mkdir -p ${stamp:h} && print $EPOCHSECONDS >| $stamp
  voz
}

(( _vozlocal_aliases )) && 'builtin' 'setopt' 'aliases'
'builtin' 'unset' '_vozlocal_aliases'
_vozlocal_startup
