// The screensaver: a phrase, a short countdown, then its meaning, over a slowly drifting, slowly dimming stage.
// The same pick as the Chrome new tab (lib voz.js), but with nothing to click: a screensaver is just watched.
import { dayNumber, key, pick, todaysChoice } from './voz.js';
import { dimAt, driftOffset, parsePersonal, readCache, writeCache } from './lib.js';

const TICK_MS = 250;
const COUNTDOWN_MS = 4000;   // the dots, before the meaning shows
const HOLD_MS = 12000;       // how long the meaning stays before the next phrase
const DRIFT_MS = 3 * 60000;  // how often the text moves
const DIM_EVERY_MS = 60000;

const $ = id => document.getElementById(id);
const started = Date.now();
const none = new Set(); // learned marks don't reach the phone yet
let region = {};
let mine = readCache(localStorage);
let last = null;
let timer;

// Called by the app (VozDream.kt) with the Worker's /phrases body, fetched natively because the Worker sends no CORS headers.
window.vozPersonal = text => {
  mine = parsePersonal(text);
  writeCache(localStorage, mine);
};

function show() {
  clearInterval(timer);
  const row = pick(todaysChoice(region, mine, none, dayNumber()).rows, none, last);
  $('stage').classList.remove('revealed');
  if (!row) {
    $('phrase').textContent = 'No phrases yet';
    $('meaning').textContent = '';
    return;
  }
  last = key(row);
  $('phrase').textContent = row[0];
  $('meaning').textContent = row[1];
  let ticks = COUNTDOWN_MS / TICK_MS;
  timer = setInterval(() => {
    if (ticks > 0) {
      $('dots').textContent = '·'.repeat(ticks--);
      return;
    }
    clearInterval(timer);
    $('dots').textContent = '';
    $('stage').classList.add('revealed');
    timer = setTimeout(show, HOLD_MS);
  }, TICK_MS);
}

const drift = () => {
  const { x, y } = driftOffset();
  $('stage').style.transform = `translate(${x}vw, ${y}vh)`;
};
const dim = () => document.body.style.setProperty('--dim', dimAt((Date.now() - started) / 60000));

async function start() {
  try {
    const phrases = await (await fetch('phrases.json')).json();
    region = phrases.es_AR ?? Object.values(phrases)[0] ?? {};
  } catch (error) {
    console.warn('VozLocal screensaver: no built-in phrases:', error);
  }
  dim();
  setInterval(dim, DIM_EVERY_MS);
  setInterval(drift, DRIFT_MS);
  show();
}

start();
