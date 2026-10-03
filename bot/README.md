# VozLocal WhatsApp bot

Message a phrase to your own WhatsApp bot, reply `yes`, and `voz sync` brings it into your terminal rotation.

```
You:  Bondi = Bus
Bot:  Save this phrase?
      Bondi → Bus
      Reply yes to save it. Anything else discards it.
You:  yes
Bot:  Saved: Bondi → Bus
```

It's a Cloudflare Worker with a D1 database. It answers only the numbers in `ALLOWED_NUMBERS`, keeps only the phrase and its meaning, and serves confirmed phrases to `voz sync` behind a token. Meta doesn't charge for its replies, because they go out inside the 24-hour window your own message opens. Cloudflare's free plan covers the rest.

## Why a Cloudflare Worker

A Worker is a function Cloudflare runs whenever a request arrives, with no server to manage, much like AWS Lambda. The two differ in where and how the code runs:

| | Cloudflare Worker | AWS Lambda |
|---|---|---|
| **Where it runs** | On Cloudflare's edge network, in hundreds of cities, near whoever calls it | In one AWS region you choose, unless you set up more |
| **How it runs** | V8 isolates, the same sandbox Chrome uses for tabs. Many Workers share one process | Each function gets its own lightweight virtual machine (Firecracker) |
| **Cold starts** | Effectively none, a few milliseconds | From about 100 ms to over a second, depending on runtime and package size |
| **Languages** | JavaScript/TypeScript, plus WebAssembly (Python support is newer) | Node, Python, Java, Go, .NET, Ruby, or any container image |
| **Limits** | Tight: small memory, CPU time per request measured in milliseconds on the free plan, no normal filesystem | Roomy: up to 10 GB memory, 15-minute runs, a temporary disk |
| **HTTPS address** | Built in: deploy and you get `*.workers.dev` | Needs a Function URL or API Gateway in front |
| **Storage next to it** | D1 (SQLite), KV, R2, Durable Objects | DynamoDB, RDS, S3, and the rest of AWS |
| **Free tier** | About 100,000 requests a day | About 1 million requests a month, plus compute time |
| **Best for** | Small, fast request handlers: webhooks, APIs, redirects, auth checks | Heavier jobs: long processing, big libraries, anything tied into other AWS services |

Limits and prices change, so check both providers' current pages before relying on these figures.

Each webhook here takes a few milliseconds of work, well within a Worker's limits. The Worker also comes with the HTTPS address Meta needs and a database with nothing extra to set up. On Lambda, the same bot would also need API Gateway or a Function URL, DynamoDB or another database, and IAM permissions to connect them. Lambda would be the better fit if the bot grew heavier, for example transcribing voice notes or running long jobs.

The code is portable. The message handling in `src/index.js` is plain JavaScript, and only the database calls and the entry point are specific to Workers.

## Message format

One phrase per message: `phrase = meaning` or `phrase | meaning`. Anything else gets a reply showing the format. Phrases already saved are reported, not stored twice. A preview waits 10 minutes for its `yes`, and sending a new phrase replaces it.

## Setup

**Follow [SETUP.md](SETUP.md).** It walks through every Cloudflare and Meta page with what each is for, the traps that make Meta's setup look finished when it isn't, a troubleshooting table, and commands that check each step.

The short version, for when you've done it before:

1. **Cloudflare:** `npm install`, `npx wrangler login`, `npx wrangler d1 create vozlocal` (paste the id into `wrangler.toml`), `npx wrangler d1 migrations apply vozlocal --remote`, `npx wrangler deploy`.
2. **Meta app:** create one with the **Connect with customers through WhatsApp** use case. Note the **Phone number ID** (not the number), the **WhatsApp Business Account ID** and the **App secret**.
3. **System user** (business.facebook.com): assign it the app *and* the WhatsApp account, both with full control. Then generate a never-expiring token with `whatsapp_business_messaging` and `whatsapp_business_management`.
4. **Register** the number (`POST /<phone number id>/register` with a PIN) and add your own number to the test number's recipient list.
5. **Webhook:** callback `https://vozlocal-bot.<you>.workers.dev/webhook` with your verify token. Subscribe the **messages** field, and link the app to the WhatsApp account (`POST /<waba id>/subscribed_apps`).
6. **Keys:** fill in `bot/.dev.vars` (see `.dev.vars.example`) and upload them with `npx wrangler secret bulk`.
7. **First message:** send yourself the `hello_world` template (you can't message a test number first), then reply `phrase = meaning`.
8. **Terminal:** set `VOZLOCAL_BOT_URL` and `VOZLOCAL_BOT_TOKEN` in `~/.zshrc` above the plugin's `source` line.

## Endpoints

| Method and path | Used by | Does |
|---|---|---|
| `GET /webhook` | Meta, once | Echoes `hub.challenge` when `hub.verify_token` matches `VERIFY_TOKEN` |
| `POST /webhook` | Meta | Checks `X-Hub-Signature-256` against `APP_SECRET`, then handles each message once |
| `GET /phrases?since=<id>` | `voz sync` | `id\|phrase\|translation` lines after `<id>`, with `Authorization: Bearer <SYNC_TOKEN>` |

## Tests

```sh
node --test bot/test
```

No packages needed: the tests run the Worker against Node's built-in SQLite, loaded with the real migration.
