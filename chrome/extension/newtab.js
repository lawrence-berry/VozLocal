// The new tab: a phrase on the left, its meaning on the right after a countdown, like voz in the terminal.
import { cleanSettings, dayNumber, key, pick, todaysRows } from './lib/voz.js';

const $ = id => document.getElementById(id);
const LANGS = { 'es-AR': 'Español (Rioplatense)', en: 'English' };
const MAX_DOTS = 24; // a long delay still counts down, without filling the panel with dots

let rows = [];
let learned = new Set();
let current = null;
let revealed = false;
let timer = null;
let settings = cleanSettings();
let saving = Promise.resolve();

const title = name => name.replace(/_/g, ' ').replace(/^./, c => c.toUpperCase());

async function start() {
  try {
    const [phrases, stored] = await Promise.all([
      fetch('data/phrases.json').then(r => r.json()),
      chrome.storage.local.get(null),
    ]);
    settings = cleanSettings(stored);
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

// Other new tabs may have changed learned since this one opened, so apply the change to what's stored now,
// one change at a time, rather than writing this tab's copy back over theirs.
function toggleLearned() {
  if (!current) return;
  const k = key(current);
  const on = !learned.has(k);
  on ? learned.add(k) : learned.delete(k);
  updateLearned();
  saving = saving.then(async () => {
    const stored = new Set(cleanSettings(await chrome.storage.local.get('learned')).learned);
    on ? stored.add(k) : stored.delete(k);
    await chrome.storage.local.set({ learned: [...stored] });
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
