# Setting up the WhatsApp bot, page by page

This is the long version of the setup in [README.md](README.md). Meta's dashboards are confusing. Several settings are spread across two different websites, and the same words ("account", "number", "ID") mean different things on different pages. Some steps look finished in the UI but aren't. Every trap below is one we actually hit.

At the end you'll have:

- the bot running on Cloudflare at `https://vozlocal-bot.<you>.workers.dev`
- a WhatsApp number (Meta's free test number to start with) that answers `phrase = meaning` messages from your phone
- `voz sync` pulling confirmed phrases into your terminal

Allow about an hour the first time. Commands are written for zsh, the macOS default, and from section 2 on **every command runs in the `bot/` folder**. Meta's menus were checked in October 2026 and change often, so labels may differ slightly. Each section says what the page is for, so you can still find it if it moves.

## Contents

1. [The pieces and how they fit](#1-the-pieces-and-how-they-fit)
2. [The six keys](#2-the-six-keys)
3. [Deploy the Worker on Cloudflare](#3-deploy-the-worker-on-cloudflare)
4. [Create the Meta app](#4-create-the-meta-app)
5. [Collect the IDs and the app secret](#5-collect-the-ids-and-the-app-secret)
6. [Create a system user and its token](#6-create-a-system-user-and-its-token)
7. [Register the phone number](#7-register-the-phone-number)
8. [Add your own number as a recipient](#8-add-your-own-number-as-a-recipient)
9. [Connect the webhook and subscribe to messages](#9-connect-the-webhook-and-subscribe-to-messages)
10. [Link the WhatsApp account to the app](#10-link-the-whatsapp-account-to-the-app)
11. [Upload the keys to Cloudflare](#11-upload-the-keys-to-cloudflare)
12. [Send the first message](#12-send-the-first-message)
13. [Point the terminal at the bot](#13-point-the-terminal-at-the-bot)
14. [Check every step from the command line](#14-check-every-step-from-the-command-line)
15. [Troubleshooting](#15-troubleshooting)
16. [Moving from the test number to a real one](#16-moving-from-the-test-number-to-a-real-one)

---

## 1. The pieces and how they fit

Meta splits the setup across two websites:

- **[developers.facebook.com](https://developers.facebook.com/apps)** ("the app dashboard"): your **app**, its webhook, its secret, the test number, the recipient list.
- **[business.facebook.com](https://business.facebook.com)** ("Business settings"): your **business portfolio**, **system users** and their tokens, and which assets each system user may touch.

```
Business portfolio  (business.facebook.com)
├── Meta app "vozLocal"  (developers.facebook.com)
│   ├── App ID, App secret ................... APP_SECRET
│   ├── Webhook: callback URL + verify token . VERIFY_TOKEN
│   │   └── Webhook fields: messages ✔  (must be subscribed separately)
│   └── Recipient list (test number only: a few verified numbers, 5 when we checked)
├── WhatsApp Business Account ("WABA")
│   ├── Phone number +1 555-…  ............... PHONE_NUMBER_ID (its ID, not the number)
│   └── Subscribed apps: vozLocal ✔  (must be linked separately)
└── System user "vozlocal-bot"
    ├── Assigned assets: the app (full control) + the WABA (full control)
    └── Permanent token ...................... WHATSAPP_TOKEN
```

A message from your phone only reaches the bot when **all** of these hold:

1. The phone number is **registered** with the Cloud API (section 7).
2. Your number is on the **recipient list** (section 8; test number only).
3. The app's webhook has the **messages** field subscribed (section 9).
4. The WABA has the app in its **subscribed apps** (section 10).
5. The Worker has the right **APP_SECRET**, or it rejects Meta's signature.

The bot's replies need two more things:

- a token whose system user has the WABA assigned (section 6)
- the right PHONE_NUMBER_ID

### Words that trip people up

| Term | What it actually is |
|---|---|
| **Business portfolio** | Your business's container in Business settings. Older pages call it "Business Manager" or "business account". |
| **Meta app** | A developer app. It owns the webhook and the app secret, and the WhatsApp settings hang off it. |
| **Use case** | Meta's newer way of grouping an app's settings. WhatsApp settings live under **Use cases → Customize** instead of a "WhatsApp" item in the sidebar. |
| **WhatsApp Business Account (WABA)** | A container for phone numbers. Not the same thing as the business portfolio, and it has its own ID. |
| **Phone number** vs **Phone number ID** | The number is what you dial (`+1 555-…`). The ID is a 15–16 digit internal number that the API needs. The two are shown next to each other and are easy to swap. |
| **System user** | A non-human user in Business settings that owns a permanent token. Its own ID looks like a phone number ID but isn't one. |
| **Webhook** | The URL Meta calls with each incoming message: `…/webhook` on the Worker. |
| **Webhook field** | A kind of event (for example **messages**) the webhook subscribes to. A webhook with a URL but no fields receives nothing. |
| **Subscribed apps** | The apps a WABA delivers events to. An empty list means nothing is delivered, whatever the webhook settings say. |
| **Test number** | A free US number Meta gives every new app. It only talks to a short list of verified recipients (5 when we checked), and the reliable way to start a chat is to have it message you first. |

---

## 2. The six keys

They all live in `bot/.dev.vars` (gitignored) and, once uploaded, in Cloudflare as Worker secrets. Create the file now, from the repo root:

```sh
cd bot
cp .dev.vars.example .dev.vars
chmod 600 .dev.vars                                 # only you can read it
openssl rand -hex 16                                # paste as VERIFY_TOKEN
openssl rand -hex 24                                # paste as SYNC_TOKEN
```

Fill in `ALLOWED_NUMBERS`, `VERIFY_TOKEN` and `SYNC_TOKEN` straight away. The other three come from Meta in sections 5 and 6. Stay in `bot/` from here on.

| Key | What it's for | Where it comes from | Looks like |
|---|---|---|---|
| `ALLOWED_NUMBERS` | The only numbers the bot answers | Your own WhatsApp number | `447700900123` (digits only, country code, no `+`) |
| `APP_SECRET` | Proves each webhook really came from Meta | App dashboard → **App settings → Basic → App secret → Show** | 32 hex characters |
| `VERIFY_TOKEN` | Meta checks it once when you save the webhook | You make it up: `openssl rand -hex 16` | 32 hex characters |
| `WHATSAPP_TOKEN` | Lets the bot send replies | Business settings → system user → **Generate new token** (section 6) | About 200 characters, starting `EAA` |
| `PHONE_NUMBER_ID` | Which number the bot replies from | App dashboard → **Quickstart** → under the **From** number | 15–16 digits. **Not** the phone number |
| `SYNC_TOKEN` | Lets `voz sync` fetch phrases | You make it up: `openssl rand -hex 24` | 48 hex characters |

You'll also see two IDs that aren't secrets but are needed during setup:

- the **App ID**, at the top of the app dashboard
- the **WhatsApp Business Account ID**, next to the phone number ID on the Quickstart page

---

## 3. Deploy the Worker on Cloudflare

Deploy first. Meta tests the webhook URL the moment you save it, so the bot must already be answering.

```sh
npm install
npx wrangler login                                  # opens your browser
npx wrangler d1 create vozlocal                     # prints a database_id
```

Paste the printed `database_id` into `wrangler.toml`, then:

```sh
npx wrangler d1 migrations apply vozlocal --remote  # creates the tables
npx wrangler deploy                                 # prints https://vozlocal-bot.<you>.workers.dev
```

Upload the three keys you already have. Each command asks for the value; paste it from `.dev.vars`. `VERIFY_TOKEN` has to be in Cloudflare before section 9, because Meta checks it when you save the webhook, and the bot refuses every check until it's set.

```sh
npx wrangler secret put VERIFY_TOKEN
npx wrangler secret put SYNC_TOKEN
npx wrangler secret put ALLOWED_NUMBERS
```

> **Trap: the URL doesn't answer at first.** On a brand-new Cloudflare account, the `*.workers.dev` subdomain can take a few minutes to start resolving. Requests fail with no HTTP status at all (`curl` shows `000`). Wait and retry. Once it works, `https://vozlocal-bot.<you>.workers.dev/` returns `Not found`, which is correct: the bot only answers on `/webhook` and `/phrases`.

---

## 4. Create the Meta app

**Page:** [developers.facebook.com/apps](https://developers.facebook.com/apps) → **Create app**

1. Name it (for example `vozLocal`).
2. When asked for a use case, choose **Connect with customers through WhatsApp**. Older flows ask for an app type instead: choose **Business**, then add the **WhatsApp** product.
3. Choose your **business portfolio**. If you don't have one, the flow creates one.

Meta then gives the app a free **test number** and a **WhatsApp Business Account** to hold it.

> **Where the WhatsApp settings live now.** Apps created with a use case have no "WhatsApp" item in the left sidebar. Everything is under **Use cases → Customize**, which has these pages:
> - **Quickstart**, called **API Setup** in older layouts: the test number, the IDs and the recipient list
> - **Configuration**: the webhook
>
> Meta's own docs still say **WhatsApp → API Setup** in places. That's the same page.

---

## 5. Collect the IDs and the app secret

### Phone number ID and WhatsApp Business Account ID

**Page:** app dashboard → **Use cases → Customize → Quickstart**, section **Send and receive messages**

Under the **From** dropdown, which shows the test number, Meta lists:

- **Phone number ID**: goes into `PHONE_NUMBER_ID`
- **WhatsApp Business Account ID**: keep it handy for section 10

> **Trap: the number instead of its ID.** The From dropdown shows `+1 555-xxx-xxxx`, and that number is not the ID. Pasting it gives Graph errors like `Object with ID '1555…' does not exist`. The ID is a separate, longer number with no `+` and no spaces.
>
> **Trap: some other ID.** Business settings is full of 15–16 digit IDs: for the system user, the business, the app. If `PHONE_NUMBER_ID` holds the wrong one, the API answers `Tried accessing nonexisting field (display_phone_number)`. Section 14 has a command that says what an ID points to.

The WABA ID is also in Business settings: **Accounts → WhatsApp accounts**. Click the account and the ID is shown at the top.

### App secret

**Page:** app dashboard → **App settings → Basic**

Click **Show** next to **App secret**. Meta may ask for your password. The value goes into `APP_SECRET`.

---

## 6. Create a system user and its token

The token on the Quickstart page is short-lived (Meta says it expires quickly). The bot needs a permanent one, which belongs to a **system user**. This part happens on the other website.

**Page:** [business.facebook.com](https://business.facebook.com) → **Settings** → **Users → System users**

### 6a. Create the system user

1. Click **Add**.
2. Give it a name (for example `vozlocal-bot`) and the **Admin** role.

### 6b. Assign the app to it

1. Select the system user, then click **Assign assets**.
2. Choose **Apps**, then tick your app.
3. Turn on **Manage app** (full control), then save.

> **Trap: "No permissions available. Assign an app role to the system user, or select another app to continue."** This appears in the token dialog when the system user has no role on the app picked there. Check these in order:
> 1. **The app belongs to your business portfolio.** Go to **Settings → Accounts → Apps**. If it isn't listed, click **Add → Connect an app ID** and enter the App ID. An app outside the portfolio can't be assigned.
> 2. **The assignment saved with full control.** Select the system user and check **Assigned assets**: the app should be listed with **Manage app** or **Full control**.
> 3. **The token dialog has the same app selected.** Meta often defaults to a different app.
> 4. **You're an Administrator on the app** (app dashboard → **App roles → Roles**).
>
> Reload the page after fixing it. The permission list doesn't refresh on its own.

### 6c. Assign the WhatsApp account to it

Easy to miss, and nothing warns you if it's skipped.

1. **Assign assets** again.
2. Choose **WhatsApp accounts**, then tick the account that holds your number.
3. Give it **Full control**, then save.

> **Trap: a token that looks fine but can't do anything.** Without this step, the token still generates with both WhatsApp permissions and reads as valid and never-expiring. But it can't see or send from any number. The `PHONE_NUMBER_ID` check in section 14 shows whether the token can reach your number.

### 6d. Generate the token

1. Select the system user, then click **Generate new token**.
2. **App:** your app (check it).
3. **Token expiration:** **Never**.
4. **Permissions:** tick `whatsapp_business_messaging` and `whatsapp_business_management`.
5. Copy the token straight into `WHATSAPP_TOKEN` in `bot/.dev.vars`. Meta shows it only once.

**Generate the token after 6b and 6c.** A token made before the WhatsApp account was assigned doesn't pick it up. Generate a new one.

---

## 7. Register the phone number

A number has to be registered with the Cloud API before it can send or receive. Meta says it registers the test number automatically, but ours wasn't. Skip this section unless you see these symptoms of an unregistered number:

- Sending fails with `(#133010) Account not registered`.
- Your phone says the number **isn't on WhatsApp**.

Register it with one call. Registering also sets a 6-digit **two-step verification PIN** for the number, so pick one and keep it (a comment in `.dev.vars` works). You only need the PIN again if you re-register.

```sh
set -a && . ./.dev.vars && set +a
print -r -- "header = \"Authorization: Bearer $WHATSAPP_TOKEN\"" |
  curl -sS -K - -H 'Content-Type: application/json' \
    -d '{"messaging_product":"whatsapp","pin":"<your 6-digit PIN>"}' \
    "https://graph.facebook.com/v26.0/$PHONE_NUMBER_ID/register"
# → {"success":true}
```

(These commands pass the token to `curl` on stdin, so it never appears in `ps` or your shell history.)

> **Trap: the register limit.** Meta allows 10 register calls per number in 72 hours. Past that, it refuses with error `133016` and blocks registration for 72 hours. Don't run this in a loop. If it fails, find out why first (section 15).

---

## 8. Add your own number as a recipient

Test numbers only talk to numbers on their recipient list (5 at most when we checked).

**Page:** app dashboard → **Use cases → Customize → Quickstart**, section **Send and receive messages**

1. Click the **To** field, then **Manage phone number list**.
2. Add your number with its country code.
3. WhatsApp sends you a code. Enter it to verify.

The number then shows as selected in **To**.

---

## 9. Connect the webhook and subscribe to messages

**Page:** app dashboard → **Use cases → Customize → Configuration**. In older layouts it's **WhatsApp → Configuration** or **WhatsApp → Webhooks**.

1. Next to **Webhook**, click **Edit**.
2. **Callback URL:** `https://vozlocal-bot.<you>.workers.dev/webhook`
3. **Verify token:** the `VERIFY_TOKEN` from `bot/.dev.vars`
4. Click **Verify and save**. Meta calls the Worker straight away; it answers only if the token matches.
5. Scroll down to **Webhook fields**, find **messages**, and click **Subscribe**.

> **Trap: the webhook is saved, but no fields are subscribed.** The callback URL can show as saved and active while **no fields** are subscribed, and then Meta sends nothing at all. The page doesn't make this obvious. Check it from the command line (section 14). You can also subscribe the field with the API:
>
> ```sh
> set -a && . ./.dev.vars && set +a
> APP_ID=<your App ID>
> print -rl -- "header = \"Authorization: Bearer $APP_ID|$APP_SECRET\"" \
>               "data-urlencode = \"verify_token=$VERIFY_TOKEN\"" |
>   curl -sS -K - \
>     --data-urlencode object=whatsapp_business_account \
>     --data-urlencode callback_url=https://vozlocal-bot.<you>.workers.dev/webhook \
>     --data-urlencode fields=messages \
>     "https://graph.facebook.com/v26.0/$APP_ID/subscriptions"
> # → {"success":true}
> ```
>
> `APP_ID|APP_SECRET` is an **app access token**. App-level settings like webhook subscriptions need it instead of the system user's token.

---

## 10. Link the WhatsApp account to the app

Even with the webhook and its fields set, Meta only delivers a WABA's messages to apps on that WABA's **subscribed apps** list. The Quickstart flow is supposed to add your app, but it doesn't always, and no page shows the list.

Check it, and add the app if the list is empty:

```sh
set -a && . ./.dev.vars && set +a
WABA_ID=<your WhatsApp Business Account ID>
# `function graph` rather than `g()`: oh-my-zsh aliases g to git, which would break a g() definition.
function graph { print -r -- "header = \"Authorization: Bearer $WHATSAPP_TOKEN\"" | curl -sS -K - "$@"; echo; }

graph "https://graph.facebook.com/v26.0/$WABA_ID/subscribed_apps"            # {"data":[]} means nothing is linked
graph -X POST "https://graph.facebook.com/v26.0/$WABA_ID/subscribed_apps"    # → {"success":true}
graph "https://graph.facebook.com/v26.0/$WABA_ID/subscribed_apps"            # now lists your app
```

---

## 11. Upload the keys to Cloudflare

Upload all six from `.dev.vars` in one go. Wrangler reads the file itself, so nothing is printed. It also overwrites the three keys from section 3 with the same values, which is harmless.

```sh
npx wrangler secret bulk .dev.vars
```

To change a single key later: `npx wrangler secret put WHATSAPP_TOKEN` (it prompts for the value). Secrets take effect straight away, with no redeploy.

---

## 12. Send the first message

> **Trap: "this number isn't on WhatsApp".** Your phone may show this when you try to start a chat with the test number. For us it happened while the number was unregistered (section 7). We didn't retest starting a chat afterwards, because the reliable route is to have the business open the chat.

Have the test number send you Meta's built-in `hello_world` template. Test numbers need no payment method to send it:

```sh
set -a && . ./.dev.vars && set +a
print -r -- "header = \"Authorization: Bearer $WHATSAPP_TOKEN\"" |
  curl -sS -K - -H 'Content-Type: application/json' \
    -d "{\"messaging_product\":\"whatsapp\",\"to\":\"${ALLOWED_NUMBERS%%,*}\",\"type\":\"template\",\"template\":{\"name\":\"hello_world\",\"language\":{\"code\":\"en_US\"}}}" \
    "https://graph.facebook.com/v26.0/$PHONE_NUMBER_ID/messages"
```

"Hello World" arrives on your phone. Reply in that chat:

```
You:  Bondi = Bus
Bot:  Save this phrase?
      Bondi → Bus
      Reply yes to save it. Anything else discards it.
You:  yes
Bot:  Saved: Bondi → Bus
```

Your reply opens a 24-hour window in which the bot's replies are free ([Meta pricing](https://developers.facebook.com/documentation/business-messaging/whatsapp/pricing)). If sending fails with `131030`, your number isn't on the recipient list yet (section 8). To watch the bot handle messages live, run `npx wrangler tail vozlocal-bot` in `bot/`.

---

## 13. Point the terminal at the bot

In `~/.zshrc`, **above** the line that sources the plugin (the plugin reads these as it loads):

```sh
export VOZLOCAL_BOT_URL=https://vozlocal-bot.<you>.workers.dev
export VOZLOCAL_BOT_TOKEN=<your SYNC_TOKEN>
```

Then run `voz sync`. You should see `voz sync: 1 new phrase`, and the phrase joins today's category in `voz`. New terminals sync in the background at most once an hour (`VOZLOCAL_SYNC_INTERVAL`).

---

## 14. Check every step from the command line

Each check maps to a step above and prints no secrets. Run them from `bot/`, starting with:

```sh
set -a && . ./.dev.vars && set +a
URL=https://vozlocal-bot.<you>.workers.dev
APP_ID=<your App ID>
WABA_ID=<your WhatsApp Business Account ID>
# `function graph` rather than `g()`: oh-my-zsh aliases g to git, which would break a g() definition.
function graph { print -r -- "header = \"Authorization: Bearer $WHATSAPP_TOKEN\"" | curl -sS -K - "$@"; echo; }
```

| What | Command | Good result |
|---|---|---|
| Worker is up (3) | `curl -s $URL/` | `Not found` |
| Webhook token matches (3, 9) | `print -rl -- "url = \"$URL/webhook\"" "data-urlencode = \"hub.verify_token=$VERIFY_TOKEN\"" \| curl -sG -K - --data 'hub.mode=subscribe&hub.challenge=ok'` | `ok` |
| Sync token works (13) | `print -r -- "header = \"Authorization: Bearer $SYNC_TOKEN\"" \| curl -s -o /dev/null -w '%{http_code}\n' -K - $URL/phrases` | `200` |
| Token is valid and permanent (6) | `print -rl -- "header = \"Authorization: Bearer $WHATSAPP_TOKEN\"" "url = \"https://graph.facebook.com/v26.0/debug_token?input_token=$WHATSAPP_TOKEN\"" \| curl -sS -K -` | `"is_valid":true`, `"expires_at":0`, both `whatsapp_…` scopes |
| PHONE_NUMBER_ID is a phone number the token can reach (5, 6c). This is also the best test of the token's access | `graph "https://graph.facebook.com/v26.0/$PHONE_NUMBER_ID?fields=display_phone_number,verified_name"` | your number, for example `"+1 555-…"` |
| What an unknown ID points to (5) | `graph "https://graph.facebook.com/v26.0/<id>?metadata=1&fields=id,name"` | the object's name (for example a system user's) |
| The WABA holds that number (5) | `graph "https://graph.facebook.com/v26.0/$WABA_ID/phone_numbers?fields=id,display_phone_number"` | lists the number and its ID |
| Webhook has the messages field (9) | `print -r -- "header = \"Authorization: Bearer $APP_ID\|$APP_SECRET\"" \| curl -sS -K - "https://graph.facebook.com/v26.0/$APP_ID/subscriptions"` | `"fields":[{"name":"messages",…}]`, `"active":true` |
| WABA delivers to the app (10) | `graph "https://graph.facebook.com/v26.0/$WABA_ID/subscribed_apps"` | lists your app |
| Phrases are stored (12) | `print -r -- "header = \"Authorization: Bearer $SYNC_TOKEN\"" \| curl -s -K - $URL/phrases` | `1\|Bondi\|Bus` |

Every check passes secrets to `curl` through its config on stdin, so none appear in `ps` or your shell history. `debug_token` still sends the token inside the request URL to Meta, because that's how the endpoint works.

---

## 15. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| **"No permissions available. Assign an app role to the system user…"** when generating a token | The system user has no role on the app picked in the dialog | Section 6b: connect the app to the portfolio, assign it with full control, pick the same app, reload |
| Graph error **`Object with ID '1555…' does not exist`** | `PHONE_NUMBER_ID` holds the phone number, not its ID | Section 5: copy the **Phone number ID** under the From number |
| Graph error **`Tried accessing nonexisting field (display_phone_number)`** | `PHONE_NUMBER_ID` holds some other ID (for example the system user's) | Section 5. Use the "what an ID points to" check in section 14 |
| Token is valid, but the `PHONE_NUMBER_ID` check fails with **`does not exist, cannot be loaded due to missing permissions`** even though the ID is right | The WhatsApp account isn't assigned to the system user, or the token predates the assignment | Section 6c, then generate a new token (6d) |
| **`(#133010) Account not registered`** | The number isn't registered with the Cloud API | Section 7 |
| Register fails with **`133005`** (PIN mismatch) | The number already has a two-step PIN and you sent a different one | Use the PIN you set before. If it's lost, reset two-step verification for the number in WhatsApp Manager |
| Register fails with **`133016`** | More than 10 register calls in 72 hours | Wait out the 72-hour block. Fix the underlying error before trying again |
| `hello_world` fails with **`131030`** (recipient not in allowed list) | Your number isn't on the test number's recipient list, or isn't verified yet | Section 8 |
| Phone says the test number **isn't on WhatsApp** | Unregistered number (possibly also: messaging the test number before it has messaged you) | Section 7, then section 12 (send `hello_world` first) |
| **Verify and save** fails in Meta | Worker not deployed yet, URL wrong (needs `/webhook`), or `VERIFY_TOKEN` differs between Meta and Cloudflare | Section 14 webhook-token check; re-upload secrets (11) |
| You message the bot and **nothing happens**, and `wrangler tail` shows no requests | Meta isn't delivering: no **messages** field subscribed, or the app isn't in the WABA's **subscribed apps** | Sections 9 and 10. Check both with section 14 |
| `wrangler tail` shows requests returning **401** | `APP_SECRET` in Cloudflare doesn't match the app's secret | Copy it again (section 5), then re-upload (11) |
| The bot receives messages but **never replies**, and the log shows `WhatsApp send failed` | Wrong `PHONE_NUMBER_ID` or token, or your number isn't on the recipient list | Sections 5, 6 and 8 |
| The bot **ignores you** but the log shows requests | Your number in `ALLOWED_NUMBERS` differs from the one WhatsApp reports (country code, extra digits) | Digits only, with country code: `447700900123` |
| `curl` to the Worker shows **`000`** right after the first deploy | A new `*.workers.dev` subdomain is still propagating | Wait a few minutes (section 3) |
| **`cd: no such file or directory: bot`** | You're already in `bot/` | Every command after section 2 runs in `bot/`; drop the `cd` |
| **`defining function based on alias`** or **`graph: command not found`** | A shell alias with the same name as the helper function | The guide uses `function graph { … }`, which aliases can't break. Paste the helper again exactly as written |
| `voz sync: could not reach the bot` | Wrong `VOZLOCAL_BOT_URL` or `VOZLOCAL_BOT_TOKEN`, or you're offline | Section 13; the sync-token check in section 14 |

---

## 16. Moving from the test number to a real one

The test number is fine for personal use with a few recipients. To use your own number instead (it must not be active on the WhatsApp app at the same time):

1. On the Quickstart page, use **Add phone number**. Set a display name, which Meta reviews, and verify the number by SMS or voice call.
2. Register it (section 7) with a new PIN.
3. Put its **Phone number ID** in `PHONE_NUMBER_ID` and re-upload (section 11). If it's in a different WABA, assign that WABA to the system user (6c) and link it to the app (10).
4. Meta may ask for a payment method on the WhatsApp account. Replies inside the 24-hour window you open are still free. See Meta's [pricing page](https://developers.facebook.com/documentation/business-messaging/whatsapp/pricing).

This section follows Meta's documented flow but hasn't been tried with this bot yet.
