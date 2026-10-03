// The new tab: a phrase on the left, its meaning on the right after a countdown, like voz in the terminal.
import { dayNumber, key, pick, todaysRows } from './lib/voz.js';

const $ = id => document.getElementById(id);
const DEFAULTS = { region: 'es_AR', delay: 2, learned: [], last: null, mine: [], swapped: false };
const LANGS = { es: 'Español (Rioplatense)', en: 'English' };

let rows = [];
let learned = new Set();
let current = null;
let revealed = false;
let timer = null;
let settings = DEFAULTS;

// Whole seconds from 0 to 30, else the default, as the terminal's VOZLOCAL_DELAY.
const delaySeconds = d => (Number.isInteger(d) && d >= 0 && d <= 30 ? d : DEFAULTS.delay);
const title = name => name.replace(/_/g, ' ').replace(/^./, c => c.toUpperCase());

async function start() {
  const [phrases, stored] = await Promise.all([
    fetch('data/phrases.json').then(r => r.json()),
    chrome.storage.local.get(DEFAULTS),
  ]);
  settings = stored;
  learned = new Set(stored.learned);
  const region = phrases[stored.region] ?? phrases[DEFAULTS.region] ?? Object.values(phrases)[0] ?? {};
  const today = todaysRows(region, stored.mine, dayNumber());
  rows = today.rows;
  $('category').textContent = today.category ? title(today.category) : 'Your phrases';

  wire();
  show(pick(rows, learned, stored.last));
}

function show(row) {
  clearInterval(timer);
  current = row;
  revealed = false;
  document.body.classList.toggle('empty', !row);
  if (!row) {
    $('left-text').textContent = 'No phrases for this region yet.';
    $('right-text').textContent = '';
    $('dots').textContent = '';
    return;
  }
  chrome.storage.local.set({ last: key(row) });
  layout();
  $('right-text').textContent = '';
  $('target').classList.remove('revealed');
  updateLearned();

  let ticks = delaySeconds(settings.delay) * 4;
  const tick = () => {
    if (ticks <= 0) return reveal();
    $('dots').textContent = '·'.repeat(ticks--);
  };
  tick();
  if (!revealed) timer = setInterval(tick, 250);
}

// Which side holds which language: Spanish first, unless swapped.
function layout() {
  const [left, right] = settings.swapped ? ['en', 'es'] : ['es', 'en'];
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
  layout();
}

function next() {
  show(pick(rows, learned, current && key(current)));
}

function toggleLearned() {
  if (!current) return;
  const k = key(current);
  learned.has(k) ? learned.delete(k) : learned.add(k);
  chrome.storage.local.set({ learned: [...learned] });
  updateLearned();
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

function wire() {
  $('target').addEventListener('click', e => { if (!e.target.closest('button')) reveal(); });
  $('next').addEventListener('click', next);
  $('learned').addEventListener('click', toggleLearned);
  $('swap').addEventListener('click', swap);
  document.addEventListener('keydown', e => {
    if (e.ctrlKey || e.metaKey || e.altKey || e.target.closest('input, textarea')) return;
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
