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

You need a Cloudflare account, a Meta developer account, and a phone number for the bot that isn't on your personal WhatsApp. To try it first, Meta's free test number works for up to five recipients you verify.

### 1. Deploy the Worker

```sh
cd bot
npm install
npx wrangler login
npx wrangler d1 create vozlocal                     # paste the printed database_id into wrangler.toml
npx wrangler d1 migrations apply vozlocal --remote
npx wrangler deploy                                 # prints https://vozlocal-bot.<you>.workers.dev
```

### 2. Create the WhatsApp app

1. At [developers.facebook.com](https://developers.facebook.com/apps), create a **Business** app and add the **WhatsApp** product.
2. Under **WhatsApp → API setup**, note the **Phone number ID** (the test number's, or your own once you add it).
3. Under **App settings → Basic**, note the **App secret**.
4. In **Business settings → System users**, create a system user and generate a permanent token with `whatsapp_business_messaging` and `whatsapp_business_management`.
5. Under **WhatsApp → Configuration**, set the callback URL to `https://vozlocal-bot.<you>.workers.dev/webhook`. Set the verify token to a random string, then subscribe to the **messages** field. Do step 3 first: Meta checks the verify token the moment you save.

### 3. Set the secrets

Each command prompts for its value:

```sh
npx wrangler secret put ALLOWED_NUMBERS   # your number, digits only, e.g. 447700900123
npx wrangler secret put APP_SECRET
npx wrangler secret put VERIFY_TOKEN      # the same random string as in Meta's webhook setup
npx wrangler secret put WHATSAPP_TOKEN
npx wrangler secret put PHONE_NUMBER_ID
npx wrangler secret put SYNC_TOKEN        # another random string, e.g. from: openssl rand -hex 24
```

For `wrangler dev`, put the same values in `bot/.dev.vars` instead (see `.dev.vars.example`; it's gitignored).

### 4. Point the terminal at it

In `~/.zshrc`, before the `source` line:

```sh
export VOZLOCAL_BOT_URL=https://vozlocal-bot.<you>.workers.dev
export VOZLOCAL_BOT_TOKEN=<your SYNC_TOKEN>
```

New terminals then sync in the background at most once an hour (`VOZLOCAL_SYNC_INTERVAL`). Run `voz sync` to sync straight away.

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
