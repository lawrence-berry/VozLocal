// The new tab: a phrase on the left, its meaning on the right after a countdown, like voz in the terminal.
import { cleanSettings, dayNumber, key, pick, queueMark, readHostReply, todaysChoice, toHex, withoutSent } from './lib/voz.js';

const $ = id => document.getElementById(id);
const LANGS = { 'es-AR': 'Español (Rioplatense)', en: 'English' };
const MAX_DOTS = 24; // a long delay still counts down, without filling the panel with dots
const HOST = 'com.vozlocal.host';
const HOST_WAIT_MS = 2000;  // per message to the host; it gives up on the learned lock sooner, after 1 s
const FIRST_WAIT_MS = 400;  // how long the page waits for the terminal before showing what it already has

let region = {};
let categoryOf = new Map();
let tabbing = false;
let markedHere = null; // the phrase on screen, if this tab's own ✓ marked it: it stays up so it can be undone  // focus was last moved with Tab, so Space on a button should press it
let learned = new Set();
let current = null;
let revealed = false;
let timer = null;
let settings = cleanSettings();
let saving = Promise.resolve();
let phrases = {};

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

// The terminal's files are the truth when the host answers. Send the marks made while it couldn't be reached,
// and, the first time it answers, the ones made before it was set up. Then read its state, and keep a copy in
// storage for when it can't be reached. Resolves to { ok } or { ok: false, error }.
async function syncWithTerminal() {
  try {
    const sent = [];
    for (const mark of settings.pending) {
      // Another tab may have sent or replaced it meanwhile; a stale mark mustn't undo a newer change.
      const queued = cleanSettings(await chrome.storage.local.get('pending')).pending;
      if (!queued.some(p => p.key === mark.key && p.on === mark.on && p.at === mark.at)) continue;
      await askHost(learnMessage(mark));
      sent.push(mark);
    }
    let state = await askHost({ op: 'state' });
    if (!settings.linked) {
      const known = new Set(state.learned);
      for (const k of settings.learned.filter(k => !known.has(k))) state = await askHost(learnMessage({ key: k, on: true }));
    }
    // Another tab may have queued marks meanwhile: keep those, drop only what was sent.
    const pending = withoutSent(cleanSettings(await chrome.storage.local.get('pending')).pending, sent);
    settings = { ...settings, learned: state.learned, mine: state.mine, pending, linked: true };
    await chrome.storage.local.set({ learned: state.learned, mine: state.mine, pending, linked: true });
    return { ok: true };
  } catch (error) {
    console.warn('VozLocal: not shared with the terminal:', error.message);
    return { ok: false, error: error.message };
  }
}

function showLink({ ok, error }) {
  const link = $('link');
  if (ok) {
    link.textContent = 'Shared with the terminal';
  } else if (/not found|forbidden/i.test(error)) {
    link.replaceChildren('Not shared with the terminal: run ', Object.assign(document.createElement('code'), { textContent: 'voz install-chrome' }));
  } else {
    link.textContent = `Not shared with the terminal (${error})`;
  }
}

// The region's phrases and their categories, with learned marks as they stand.
function build() {
  learned = new Set(settings.learned);
  region = phrases[settings.region] ?? phrases.es_AR ?? Object.values(phrases)[0] ?? {};
  categoryOf = new Map(Object.entries(region).flatMap(([name, list]) => list.map(r => [key(r), title(name)])));
}

// Never a learned phrase, and worked out afresh each time, so a phrase just marked ✓ can't come up next.
const choose = last => pick(todaysChoice(region, settings.mine, learned, dayNumber()).rows, learned, last);

async function start() {
  try {
    let stored;
    [phrases, stored] = await Promise.all([
      fetch('data/phrases.json').then(r => r.json()),
      chrome.storage.local.get(null),
    ]);
    settings = cleanSettings(stored);
    // Usually the terminal answers in a few dozen ms, in time to skip a phrase just learned with yas. If it's
    // slow, show what's stored now and take its answer when it comes.
    const syncing = syncWithTerminal();
    const first = await Promise.race([syncing, new Promise(done => setTimeout(done, FIRST_WAIT_MS))]);
    build();
    // A ✓ pressed before the sync is done waits for it, so the sync can't write older marks over it.
    saving = syncing.then(() => {}, () => {});
    wire();
    show(choose(settings.last));
    if (first) {
      showLink(first);
    } else {
      syncing.then(result => {
        refresh();
        showLink(result);
      }).catch(error => console.warn('VozLocal could not apply the terminal\'s answer:', error));
    }
  } catch (error) {
    console.warn('VozLocal could not start:', error);
    show(null);
  }
}

// After learned marks or mine.psv change outside this tab's own ✓ (the terminal's answer, yas, another tab):
// move on if the phrase on screen is now learned, or if new phrases ended the "all learned" page.
function refresh() {
  build();
  if (!current || (learned.has(key(current)) && key(current) !== markedHere)) show(choose(current && key(current)));
  else updateLearned();
}

function show(row) {
  clearInterval(timer);
  current = row;
  markedHere = null;
  revealed = false;
  document.body.classList.toggle('empty', !row);
  $('dots').textContent = '';
  $('right-text').textContent = '';
  if (!row) {
    const done = Object.keys(region).length > 0;
    $('category').textContent = done ? 'All learned' : 'No phrases';
    $('left-text').textContent = done ? '¡Bien ahí! You\'ve learned every phrase. Send new ones on WhatsApp to keep going.' : 'No phrases to show yet.';
    $('target').classList.add('revealed');
    $('target').removeAttribute('title');
    return;
  }
  chrome.storage.local.set({ last: key(row) });
  // The category it came from, which isn't today's when today's are all learned.
  $('category').textContent = categoryOf.get(key(row)) ?? 'Your phrases';
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
  show(choose(current && key(current)));
}

// Save the mark to the terminal's learned file through the host, one change at a time. If the host can't be
// reached, keep it in storage and queue it for the next new tab. Either way, apply it to what's stored now
// rather than writing this tab's copy over another tab's.
function toggleLearned() {
  if (!current) return;
  const k = key(current);
  const on = !learned.has(k);
  on ? learned.add(k) : learned.delete(k);
  markedHere = on ? k : null;
  updateLearned();
  saving = saving.then(async () => {
    try {
      const state = await askHost(learnMessage({ key: k, on }));
      await chrome.storage.local.set({ learned: state.learned, mine: state.mine });
      showLink({ ok: true });
    } catch (error) {
      const stored = cleanSettings(await chrome.storage.local.get(['learned', 'pending']));
      const marks = new Set(stored.learned);
      on ? marks.add(k) : marks.delete(k);
      await chrome.storage.local.set({ learned: [...marks], pending: queueMark(stored.pending, k, on, Date.now()) });
      showLink({ ok: false, error: error.message });
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
  if (changes.learned || changes.mine) {
    const fresh = cleanSettings({ learned: changes.learned?.newValue ?? settings.learned, mine: changes.mine?.newValue ?? settings.mine });
    settings = { ...settings, learned: fresh.learned, mine: fresh.mine };
    refresh();
  }
  if (changes.swapped) {
    settings = { ...settings, swapped: changes.swapped.newValue === true };
    layout();
  }
}

function wire() {
  chrome.storage.onChanged.addListener(follow);
  $('target').addEventListener('click', e => { if (!e.target.closest('button')) reveal(); });
  // A button clicked with the mouse lets go of focus, or the next Space would press it again.
  const button = (id, action) => $(id).addEventListener('click', e => { if (e.detail) e.currentTarget.blur(); action(); });
  button('next', next);
  button('learned', toggleLearned);
  button('swap', swap);
  document.addEventListener('keydown', e => { if (e.key === 'Tab') tabbing = true; }, true);
  document.addEventListener('pointerdown', () => { tabbing = false; }, true);
  document.addEventListener('keydown', e => {
    if (e.ctrlKey || e.metaKey || e.altKey || e.target.closest('input, textarea')) return;
    // Space presses a button only if it was reached with Tab; otherwise it reveals, then moves on.
    if (e.key === ' ' && tabbing && e.target.closest('button')) return;
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
