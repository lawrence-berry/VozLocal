// Run: node --test bot/test   (Node 22.5+, no packages needed)
import { test, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createHmac } from 'node:crypto';
import { DatabaseSync } from 'node:sqlite';
import worker, { parse } from '../src/index.js';

// Enough of D1's API over node:sqlite, loaded with the real migration.
function fakeD1() {
  const db = new DatabaseSync(':memory:');
  db.exec(readFileSync(new URL('../migrations/0001_init.sql', import.meta.url), 'utf8'));
  return {
    prepare(sql) {
      const stmt = db.prepare(sql);
      let args = [];
      const api = {
        bind(...a) { args = a; return api; },
        async first() { return stmt.get(...args) ?? null; },
        async run() { return { meta: { changes: Number(stmt.run(...args).changes) } }; },
        async all() { return { results: stmt.all(...args) }; },
      };
      return api;
    },
  };
}

const ME = '447700900123', STRANGER = '447700900999';
let env, sent;

beforeEach(() => {
  env = {
    DB: fakeD1(), APP_SECRET: 'app-secret', VERIFY_TOKEN: 'verify-me', SYNC_TOKEN: 'sync-token',
    WHATSAPP_TOKEN: 'wa-token', PHONE_NUMBER_ID: '1234', GRAPH_VERSION: 'v99.0', ALLOWED_NUMBERS: `+${ME}`,
  };
  sent = [];
  globalThis.fetch = async (url, init) => { sent.push({ url, ...JSON.parse(init.body) }); return new Response('{}'); };
});

let nextId = 0;
function webhook(text, { from = ME, secret = env.APP_SECRET, type = 'text', id = `wamid.${++nextId}`, ctx, timestamp } = {}) {
  const message = { from, id, type, ...(timestamp ? { timestamp } : {}), ...(type === 'text' ? { text: { body: text } } : {}) };
  const body = JSON.stringify({ entry: [{ changes: [{ value: { messages: [message] } }] }] });
  const sig = 'sha256=' + createHmac('sha256', secret).update(body).digest('hex');
  return worker.fetch(new Request('https://bot.test/webhook', { method: 'POST', body, headers: { 'X-Hub-Signature-256': sig } }), env, ctx);
}
const say = async (text, opts) => { sent = []; await webhook(text, opts); return sent.at(-1)?.text.body; };
const phrases = (since = '0', token = env.SYNC_TOKEN) =>
  worker.fetch(new Request(`https://bot.test/phrases?since=${since}`, { headers: { Authorization: `Bearer ${token}` } }), env);

test('a phrase is stored only after yes', async () => {
  assert.match(await say('Bondi = Bus'), /Save this phrase\?\nBondi → Bus\nReply yes/);
  assert.equal(await (await phrases()).text(), '');
  assert.equal(await say('Yes!'), 'Saved: Bondi → Bus');
  assert.equal(await (await phrases()).text(), '1|Bondi|Bus\n');
});

test('replies go to the sender through the Graph API', async () => {
  await say('Bondi = Bus');
  assert.equal(sent[0].url, 'https://graph.facebook.com/v99.0/1234/messages');
  assert.equal(sent[0].to, ME);
  assert.equal(sent[0].type, 'text');
});

test('anything but yes discards the pending phrase', async () => {
  await say('Bondi = Bus');
  assert.match(await say('no'), /^Discarded: Bondi/);
  assert.match(await say('yes'), /^Nothing to save/);
  assert.equal(await (await phrases()).text(), '');
});

test('a new phrase replaces the pending one', async () => {
  await say('Bondi = Bus');
  await say('Chamuyo | Sweet talk');
  await say('sí');
  assert.equal(await (await phrases()).text(), '1|Chamuyo|Sweet talk\n');
});

test('duplicates are reported, not stored twice', async () => {
  await say('Bondi = Bus'); await say('yes');
  assert.equal(await say('Bondi = Colectivo'), 'Already saved: Bondi');
  assert.equal(await (await phrases()).text(), '1|Bondi|Bus\n');
});

test('messages from other numbers are ignored', async () => {
  await say('Bondi = Bus', { from: STRANGER });
  await say('yes', { from: STRANGER });
  assert.equal(sent.length, 0);
  assert.equal(await (await phrases()).text(), '');
});

test('a retried webhook is acted on once', async () => {
  await say('Bondi = Bus');
  const res = await webhook('yes', { id: 'wamid.retry' });
  assert.equal(res.status, 200);
  sent = [];
  await webhook('yes', { id: 'wamid.retry' });
  assert.equal(sent.length, 0);
});

test('a bad signature is refused and changes nothing', async () => {
  const res = await webhook('Bondi = Bus', { secret: 'wrong' });
  assert.equal(res.status, 401);
  assert.equal(sent.length, 0);
});

test('non-text messages get the format help', async () => {
  assert.match(await say('', { type: 'image' }), /phrase = meaning/);
});

test('parse refuses lines that would break a .psv file or the terminal', () => {
  assert.deepEqual(parse('Che = Hey'), { phrase: 'Che', translation: 'Hey' });
  assert.deepEqual(parse('a = b = c'), { phrase: 'a', translation: 'b = c' });
  for (const bad of ['', 'no separator', ' = meaning', 'phrase = ', 'a = b | c', 'a = b\nc', 'a = \x1b[31mred', 'a = \u009b31m',
    'a\u202e = b', 'a\u200b = b', 'a\ufeffb = c', 'a = b\u2028c', `${'x'.repeat(201)} = y`]) {
    assert.ok(parse(bad).error, JSON.stringify(bad));
  }
});

test('/phrases needs the sync token and pages by id', async () => {
  await say('Bondi = Bus'); await say('yes');
  await say('Che = Hey'); await say('yes');
  assert.equal((await phrases('0', 'wrong')).status, 401);
  assert.equal(await (await phrases('1')).text(), '2|Che|Hey\n');
  assert.equal(await (await phrases('junk')).text(), '1|Bondi|Bus\n2|Che|Hey\n');
});

test('webhook verification echoes the challenge only with the right token', async () => {
  const verify = token => worker.fetch(new Request(`https://bot.test/webhook?hub.mode=subscribe&hub.verify_token=${token}&hub.challenge=42`), env);
  assert.equal(await (await verify('verify-me')).text(), '42');
  assert.equal((await verify('nope')).status, 403);
});

test('a confirmed phrase survives a failed store: the retried yes saves it', async () => {
  await say('Bondi = Bus');
  const db = env.DB;
  let fail = true;
  env.DB = { prepare(sql) {
    if (fail && sql.startsWith('INSERT INTO phrases')) { fail = false; return { bind: () => ({ run: async () => { throw new Error('D1 hiccup'); } }) }; }
    return db.prepare(sql);
  } };
  await assert.rejects(webhook('yes', { id: 'wamid.flaky' }), /D1 hiccup/);
  assert.equal(await say('yes', { id: 'wamid.flaky' }), 'Saved: Bondi → Bus');
});

test('a preview lapses after ten minutes', async () => {
  await say('Bondi = Bus');
  await env.DB.prepare('UPDATE pending SET created_at = created_at - 601').run();
  assert.match(await say('yes'), /^Nothing to save/);
  assert.equal(await (await phrases()).text(), '');
});

test('a new phrase says which pending one it replaced', async () => {
  await say('Bondi = Bus');
  assert.match(await say('Che = Hey'), /^Discarded: Bondi\nSave this phrase\?\nChe → Hey/);
});

test('non-ASCII text passes the signature check and is stored as sent', async () => {
  await say('Ñandú = Rhea'); await say('sí');
  assert.equal(await (await phrases()).text(), '1|Ñandú|Rhea\n');
});

test('replies are handed to waitUntil when the runtime offers it', async () => {
  const later = [];
  const res = await webhook('Bondi = Bus', { ctx: { waitUntil: p => later.push(p) } });
  assert.equal(res.status, 200);
  assert.equal(later.length, 1);
  await Promise.all(later);
  assert.match(sent.at(-1).text.body, /^Save this phrase/);
});

test('old message ids are forgotten', async () => {
  await env.DB.prepare('INSERT INTO seen (message_id, created_at) VALUES (?, ?)').bind('wamid.old', 0).run();
  await say('Bondi = Bus');
  assert.equal(await env.DB.prepare('SELECT 1 FROM seen WHERE message_id = ?').bind('wamid.old').first(), null);
});

test('a yes sent in time but retried after the preview lapsed still saves', async () => {
  await say('Bondi = Bus');
  await env.DB.prepare('UPDATE pending SET created_at = created_at - 3600').run();
  const sentAt = String(Math.floor(Date.now() / 1000) - 3300);  // 55 minutes after the preview
  assert.equal(await say('yes', { timestamp: sentAt }), 'Saved: Bondi → Bus');
});
