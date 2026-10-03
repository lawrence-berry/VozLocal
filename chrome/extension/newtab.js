// The new tab: a phrase on the left, its meaning on the right after a countdown, like voz in the terminal.
import { cleanSettings, dayNumber, key, pick, readHostReply, todaysRows, toHex } from './lib/voz.js';

const $ = id => document.getElementById(id);
const LANGS = { 'es-AR': 'Español (Rioplatense)', en: 'English' };
const MAX_DOTS = 24; // a long delay still counts down, without filling the panel with dots
const HOST = 'com.vozlocal.host';
const HOST_WAIT_MS = 1500;

let rows = [];
let learned = new Set();
let current = null;
let revealed = false;
let timer = null;
let settings = cleanSettings();
let saving = Promise.resolve();

const title = name => name.replace(/_/g, ' ').replace(/^./, c => c.toUpperCase());

// Ask the terminal's host (vozlocal-host, set up by `voz install-chrome`). Resolves to its learned keys and
// mine.psv rows, or rejects if it isn't installed, fails, or takes too long.
async function askHost(message) {
  let timeout;
  const late = new Promise((_, reject) => { timeout = setTimeout(() => reject(new Error('no reply')), HOST_WAIT_MS); });
  try {
    const reply = await Promise.race([chrome.runtime.sendNativeMessage(HOST, { region: settings.region, ...message }), late]);
    const state = readHostReply(reply);
    if (!state) throw new Error(reply?.error ?? 'bad reply');
    return state;
  } finally {
    clearTimeout(timeout);
  }
}

const learnMessage = ({ key: k, on }) => ({ op: 'learn', key: toHex(k), on });

// The terminal's files are the truth when the host answers: send marks made while it couldn't, then read its
// state, and keep a copy in storage for when it can't be reached. Returns false if it couldn't be reached.
async function syncWithTerminal() {
  try {
    let state;
    const pending = [...settings.pending];
    while (pending.length) {
      state = await askHost(learnMessage(pending[0]));
      pending.shift();
    }
    state = await askHost({ op: 'state' });
    settings = { ...settings, learned: state.learned, mine: state.mine, pending: [] };
    await chrome.storage.local.set({ learned: state.learned, mine: state.mine, pending: [] });
    return true;
  } catch (error) {
    console.warn('VozLocal: not linked to the terminal:', error.message);
    return false;
  }
}

function showLink(linked) {
  const link = $('link');
  if (linked) {
    link.textContent = 'Shared with the terminal';
  } else {
    link.replaceChildren('Not shared with the terminal: run ', Object.assign(document.createElement('code'), { textContent: 'voz install-chrome' }));
  }
}

async function start() {
  try {
    const [phrases, stored] = await Promise.all([
      fetch('data/phrases.json').then(r => r.json()),
      chrome.storage.local.get(null),
    ]);
    settings = cleanSettings(stored);
    const linked = await syncWithTerminal();
    showLink(linked);
    learned = new Set(settings.learned);
    const region = phrases[settings.region] ?? phrases.es_AR ?? Object.values(phrases)[0] ?? {};
    const today = todaysRows(region, settings.mine, dayNumber());
    rows = today.rows;
    $('category').textContent = today.category ? title(today.category) : 'Your phrases';
    wire();
    show(pick(rows, learned, settings.last));
  } catch (error) {
    console.warn('VozLocal could not start:', error);
    show(null);
  }
}

function show(row) {
  clearInterval(timer);
  current = row;
  revealed = false;
  document.body.classList.toggle('empty', !row);
  $('dots').textContent = '';
  $('right-text').textContent = '';
  if (!row) {
    $('left-text').textContent = 'No phrases to show yet.';
    $('target').classList.add('revealed');
    $('target').removeAttribute('title');
    return;
  }
  chrome.storage.local.set({ last: key(row) });
  $('target').classList.remove('revealed');
  $('target').title = 'Click to reveal (Space)';
  layout();
  updateLearned();

  let ticks = settings.delay * 4;
  const tick = () => {
    if (ticks <= 0) return reveal();
    $('dots').textContent = '·'.repeat(Math.min(ticks--, MAX_DOTS));
  };
  tick();
  if (!revealed) timer = setInterval(tick, 250);
}

// Which side holds which language: Spanish first, unless swapped.
function layout() {
  const [left, right] = settings.swapped ? ['en', 'es-AR'] : ['es-AR', 'en'];
  $('lang-left').textContent = LANGS[left];
  $('lang-right').textContent = LANGS[right];
  $('left-text').lang = left;
  $('right-text').lang = right;
  if (!current) return;
  const [phrase, meaning] = current;
  $('left-text').textContent = settings.swapped ? meaning : phrase;
  if (revealed) $('right-text').textContent = settings.swapped ? phrase : meaning;
}

function reveal() {
  if (!current || revealed) return;
  clearInterval(timer);
  revealed = true;
  $('dots').textContent = '';
  $('target').classList.add('revealed');
  $('target').removeAttribute('title');
  layout();
}

function next() {
  if (rows.length) show(pick(rows, learned, current && key(current)));
}

// Save the mark to the terminal's learned file through the host, one change at a time. If the host can't be
// reached, keep it in storage and queue it for the next new tab. Either way, apply it to what's stored now
// rather than writing this tab's copy over another tab's.
function toggleLearned() {
  if (!current) return;
  const k = key(current);
  const on = !learned.has(k);
  on ? learned.add(k) : learned.delete(k);
  updateLearned();
  saving = saving.then(async () => {
    try {
      const state = await askHost(learnMessage({ key: k, on }));
      await chrome.storage.local.set({ learned: state.learned, mine: state.mine });
      showLink(true);
    } catch {
      const stored = cleanSettings(await chrome.storage.local.get(['learned', 'pending']));
      const marks = new Set(stored.learned);
      on ? marks.add(k) : marks.delete(k);
      await chrome.storage.local.set({ learned: [...marks], pending: [...stored.pending, { key: k, on }] });
      showLink(false);
    }
  }).catch(error => console.warn('VozLocal could not save learned:', error));
}

function updateLearned() {
  const on = !!current && learned.has(key(current));
  $('learned').setAttribute('aria-pressed', String(on));
  $('learned').title = on ? 'Learned. Click to undo (L)' : 'Mark as learned (L)';
}

function swap() {
  settings = { ...settings, swapped: !settings.swapped };
  chrome.storage.local.set({ swapped: settings.swapped });
  layout();
}

// Keep in step with other new tabs: learned marks and the swap apply everywhere.
function follow(changes, area) {
  if (area !== 'local') return;
  if (changes.learned) {
    learned = new Set(cleanSettings({ learned: changes.learned.newValue }).learned);
    updateLearned();
  }
  if (changes.swapped) {
    settings = { ...settings, swapped: changes.swapped.newValue === true };
    layout();
  }
}

function wire() {
  chrome.storage.onChanged.addListener(follow);
  $('target').addEventListener('click', e => { if (!e.target.closest('button')) reveal(); });
  $('next').addEventListener('click', next);
  $('learned').addEventListener('click', toggleLearned);
  $('swap').addEventListener('click', swap);
  document.addEventListener('keydown', e => {
    if (e.ctrlKey || e.metaKey || e.altKey || e.target.closest('input, textarea')) return;
    // Space on a button reached with the keyboard presses that button, as usual.
    if (e.key === ' ' && e.target.matches('button:focus-visible')) return;
    const action = {
      ' ': () => (revealed ? next() : reveal()),
      n: next,
      l: toggleLearned,
      s: swap,
    }[e.key.toLowerCase()];
    if (!action) return;
    e.preventDefault();
    if (e.repeat) return;
    action();
  });
}

start();
