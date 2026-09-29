# vozlocal: show a Spanish phrase, pause, then reveal the translation. See README.md.

VOZLOCAL_HOME=${${(%):-%x}:A:h}
zmodload zsh/datetime

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
  local -a files=( $VOZLOCAL_HOME/data/${VOZLOCAL_REGION:-es_AR}/*.psv(N) )
  (( $#files )) || { print -u2 "vozlocal: no .psv files found"; return 1 }

  local dir=${XDG_CACHE_HOME:-$HOME/.cache}/vozlocal idx line
  local -a src
  idx=$(_vozlocal_category $#files $(( EPOCHSECONDS / 86400 )))
  src=( $files[idx] )
  [[ -r $dir/learned ]] && src=( $dir/learned $src )
  # Skip learned phrases (whole lines in $dir/learned), unless every phrase in the category is learned.
  # Read $RANDOM here, not inside $( ): subshells all see the same value, so repeated voz calls would repeat.
  local seed=$RANDOM
  line=$(awk -v seed=$seed -v learned=$dir/learned '
    FILENAME == learned { done[$0]; next }
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

# Auto-show in interactive terminals, at most once per VOZLOCAL_INTERVAL minutes (0 = every shell).
() {
  emulate -L zsh
  [[ -o interactive && -t 1 ]] || return 0
  local stamp=${XDG_CACHE_HOME:-$HOME/.cache}/vozlocal/last_shown last
  [[ -r $stamp ]] && last=$(<$stamp)
  [[ $last == <-> ]] || last=0
  _vozlocal_int VOZLOCAL_INTERVAL 30
  (( REPLY && EPOCHSECONDS - last < REPLY * 60 )) && return
  mkdir -p ${stamp:h} && print $EPOCHSECONDS >| $stamp
  voz
}
