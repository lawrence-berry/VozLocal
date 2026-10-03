// VozLocal WhatsApp bot: a Cloudflare Worker that receives Meta's webhook, asks you to confirm each
// phrase, stores confirmed ones in D1, and serves them to `voz sync`. See bot/README.md.

const MAX_LEN = 200;
const PENDING_TTL = 10 * 60;        // seconds a preview waits for its yes
const SEEN_TTL = 7 * 24 * 60 * 60;  // seconds a message id is remembered, well past Meta's retries
const YES = /^(yes|y|si|sí)[.!]*$/i;
const HELP = 'Send a phrase as: phrase = meaning\nFor example: Bondi = Bus';

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    if (url.pathname === '/webhook' && request.method === 'GET') return verifySubscription(url, env);
    if (url.pathname === '/webhook' && request.method === 'POST') return receive(request, env, ctx);
    if (url.pathname === '/phrases' && request.method === 'GET') return listPhrases(request, url, env);
    return new Response('Not found', { status: 404 });
  },
};

// Meta calls GET /webhook once, when the webhook is registered, to check we know the verify token.
function verifySubscription(url, env) {
  const ok = url.searchParams.get('hub.mode') === 'subscribe'
    && safeEqual(url.searchParams.get('hub.verify_token') ?? '', env.VERIFY_TOKEN);
  return ok ? new Response(url.searchParams.get('hub.challenge') ?? '') : new Response('Forbidden', { status: 403 });
}

async function receive(request, env, ctx) {
  // The signature covers the exact bytes Meta sent, so check those before decoding them.
  const body = new Uint8Array(await request.arrayBuffer());
  if (!await validSignature(body, request.headers.get('X-Hub-Signature-256'), env.APP_SECRET)) {
    return new Response('Bad signature', { status: 401 });
  }
  let payload;
  try { payload = JSON.parse(new TextDecoder().decode(body)); } catch { return new Response('Bad JSON', { status: 400 }); }

  const allowed = new Set(String(env.ALLOWED_NUMBERS ?? '').split(',').map(digits).filter(Boolean));
  for (const entry of payload.entry ?? []) {
    for (const change of entry.changes ?? []) {
      for (const message of change.value?.messages ?? []) {
        if (!allowed.has(digits(message.from))) continue;  // Only your own number gets an answer.
        if (await env.DB.prepare('SELECT 1 FROM seen WHERE message_id = ?').bind(message.id).first()) continue;
        const reply = await handle(env.DB, message);
        await env.DB.prepare('INSERT OR IGNORE INTO seen (message_id, created_at) VALUES (?, ?)')
          .bind(message.id, now()).run();
        // Reply after responding, so a slow Graph API call can't push Meta's webhook into a timeout.
        const sending = send(env, message.from, reply);
        if (ctx?.waitUntil) ctx.waitUntil(sending); else await sending;
      }
    }
  }
  await env.DB.prepare('DELETE FROM seen WHERE created_at < ?').bind(now() - SEEN_TTL).run();
  return new Response('OK');
}

// Returns the reply text for one message, updating pending and stored phrases on the way.
export async function handle(db, message) {
  const sender = digits(message.from);
  const text = message.type === 'text' ? String(message.text?.body ?? '').trim() : '';
  const clearPending = () => db.prepare('DELETE FROM pending WHERE sender = ?').bind(sender).run();
  // A preview older than PENDING_TTL has lapsed, so a stray yes days later can't save it. Measured from when
  // WhatsApp says the message was sent, so a yes that Meta retries hours later still counts.
  const sentAt = /^\d+$/.test(message.timestamp ?? '') ? Math.min(Number(message.timestamp), now()) : now();
  const pending = await db.prepare('SELECT phrase, translation FROM pending WHERE sender = ? AND created_at >= ?')
    .bind(sender, sentAt - PENDING_TTL).first();

  if (pending && YES.test(text)) {
    // Store before clearing: if the store fails, Meta retries the yes and the pending phrase is still there.
    const { meta } = await db.prepare(
      'INSERT INTO phrases (phrase, translation, created_at) VALUES (?, ?, ?) ON CONFLICT (phrase) DO NOTHING',
    ).bind(pending.phrase, pending.translation, now()).run();
    await clearPending();
    return meta.changes ? `Saved: ${pending.phrase} → ${pending.translation}` : `Already saved: ${pending.phrase}`;
  }

  const parsed = parse(text);
  if (parsed.error) {
    if (pending) await clearPending();
    if (!pending && YES.test(text)) return `Nothing to save.\n${HELP}`;
    return pending ? `Discarded: ${pending.phrase}\n${parsed.error}` : parsed.error;
  }

  if (await db.prepare('SELECT 1 FROM phrases WHERE phrase = ?').bind(parsed.phrase).first()) {
    if (pending) await clearPending();
    return `Already saved: ${parsed.phrase}`;
  }
  await db.prepare(
    'INSERT INTO pending (sender, phrase, translation, created_at) VALUES (?, ?, ?, ?) '
    + 'ON CONFLICT (sender) DO UPDATE SET phrase = excluded.phrase, translation = excluded.translation, created_at = excluded.created_at',
  ).bind(sender, parsed.phrase, parsed.translation, now()).run();
  return `${pending ? `Discarded: ${pending.phrase}\n` : ''}Save this phrase?\n${parsed.phrase} → ${parsed.translation}\nReply yes to save it. Anything else discards it.`;
}

// `phrase = meaning` or `phrase | meaning`, split at the first separator. Refuses anything that would
// break a .psv line, reach the terminal as a control sequence, or reorder or hide text (bidi and zero-width marks).
export function parse(text) {
  const at = text.search(/[=|]/);
  if (!text || at < 0) return { error: HELP };
  const phrase = text.slice(0, at).trim(), translation = text.slice(at + 1).trim();
  if (!phrase || !translation) return { error: HELP };
  if (/[|\p{Cc}\p{Cf}\u2028\u2029]/u.test(phrase + translation)) return { error: `Use one line, and no | inside the phrase or meaning.\n${HELP}` };
  if (phrase.length > MAX_LEN || translation.length > MAX_LEN) return { error: `Keep the phrase and meaning under ${MAX_LEN} characters each.` };
  return { phrase, translation };
}

// GET /phrases?since=<id> → `id|phrase|translation` lines, oldest first. Bearer SYNC_TOKEN required.
async function listPhrases(request, url, env) {
  const auth = request.headers.get('Authorization') ?? '';
  if (!env.SYNC_TOKEN || !safeEqual(auth, `Bearer ${env.SYNC_TOKEN}`)) return new Response('Unauthorized', { status: 401 });
  const since = /^\d+$/.test(url.searchParams.get('since') ?? '') ? Number(url.searchParams.get('since')) : 0;
  const { results } = await env.DB.prepare(
    'SELECT id, phrase, translation FROM phrases WHERE id > ? ORDER BY id LIMIT 1000',
  ).bind(since).all();
  const lines = results.map(r => `${r.id}|${r.phrase}|${r.translation}\n`).join('');
  return new Response(lines, { headers: { 'Content-Type': 'text/plain; charset=utf-8' } });
}

// A free-form reply. Meta doesn't charge for these inside the 24-hour window your message opens.
async function send(env, to, body) {
  const res = await fetch(`https://graph.facebook.com/${env.GRAPH_VERSION}/${env.PHONE_NUMBER_ID}/messages`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${env.WHATSAPP_TOKEN}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ messaging_product: 'whatsapp', to, type: 'text', text: { body } }),
  });
  if (!res.ok) console.error(`WhatsApp send failed: ${res.status} ${await res.text()}`);
}

async function validSignature(body, header, secret) {
  if (!secret || !header?.startsWith('sha256=')) return false;
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const mac = await crypto.subtle.sign('HMAC', key, body);
  const hex = [...new Uint8Array(mac)].map(b => b.toString(16).padStart(2, '0')).join('');
  return safeEqual(header.slice(7), hex);
}

function safeEqual(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string' || !b || a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

const digits = s => String(s ?? '').replace(/\D/g, '');
const now = () => Math.floor(Date.now() / 1000);
