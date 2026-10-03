# VozLocal for Chrome

A new tab page that shows a Rioplatense Spanish phrase, then its translation, like `voz` in the terminal. It's laid out like Google Translate, and it shares learned phrases and your WhatsApp phrases with the terminal.

## Install

1. Open `chrome://extensions` and turn on **Developer mode**.
2. Click **Load unpacked** and choose the `chrome/extension` folder.
3. Open a new tab. Chrome asks once whether to keep the change; keep it.
4. To see it when Chrome starts as well: Settings › On startup › **Open the New Tab page**.

After pulling changes, click the reload arrow on the extension's card.

## Sharing with the terminal

With the terminal plugin installed, run this once:

```sh
voz install-chrome
```

From then on, both read the same files:
- **Learned phrases:** `~/.cache/vozlocal/learned`. A phrase you `yas` in the terminal doesn't show in the next tab, and ✓ in Chrome adds to the same file.
- **Your phrases:** `terminal/data/<region>/mine.psv`, which `voz sync` fills from the WhatsApp bot. Run `voz install-cron` to sync every 15 minutes even when no terminal is open.

**How it works.** Chrome can't read files on disk, so `voz install-chrome` registers `terminal/vozlocal-host` as a [native messaging host](https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging). It writes two files into Chrome's `NativeMessagingHosts` folder:
- a manifest that only lets this extension call the host. The `key` in `manifest.json` fixes the extension's id, so moving this folder doesn't matter;
- a launcher that gives the host your shell's paths, since Chrome starts it without your `.zshrc`.

If you move the repo, run `voz install-chrome` again.

**The first time it links,** any phrases you marked ✓ in Chrome before are added to the terminal's learned file, so nothing is lost.

**When it isn't linked.** The page says "Not shared with the terminal" at the bottom right, with the reason, and keeps working on its own copy. Marks made then are sent to the terminal on the first new tab after it's linked again.

**Speed.** Each new tab waits up to 0.4 s for the terminal's answer, which usually takes a few dozen milliseconds. If it's slower, the page shows what it already has and takes the answer when it comes.

## Using it

Each new tab picks a phrase from today's category. The meaning appears after a 2-second countdown.

| Key | Button | Does |
|---|---|---|
| Space | click the right panel | Reveal now; once revealed, the next phrase |
| N | → | Next phrase |
| L | ✓ | Mark as learned, so it isn't picked again; press again to undo |
| S | ⇄ | Swap the languages, so the English comes first |

It never shows the same phrase twice in a row. Learned phrases come back only when a category has nothing else left.

## Layout

| Path | What |
|---|---|
| `extension/` | The extension Chrome loads |
| `extension/lib/voz.js` | Picking the day's category and phrase, and reading the bot's `/phrases` rows. No DOM, so it's tested in Node |
| `extension/newtab.*` | The page. Styles copy Google Translate's, with Google Sans bundled in `extension/fonts` (SIL Open Font License) |
| `extension/data/phrases.json` | `terminal/data` bundled as JSON, made by `bin/build-data`. Don't edit it by hand |
| `bin/build-data` | Rebuilds `phrases.json`. `--check` fails if it's out of date |
| `bin/build-icons` | Renders `assets/logo.svg` as the extension's icons, in Chromium |
| `bin/dev` | Runs a command in the Docker image (Ruby 3.4, Node and Playwright's Chromium), so nothing uses the system Ruby |
| `test/` | Node tests for `voz.js` |
| `spec/` | RSpec specs, including Playwright specs that load the extension in Chromium |

## Phrases

Both apps read the same phrases. The shipped ones live in `terminal/data`, and the extension carries a copy in `phrases.json`. After changing a shipped `.psv` file, run:

```sh
chrome/bin/dev bin/build-data
```

A spec fails if you forget. Your own phrases (`mine.psv`) aren't copied: the extension reads them from the terminal, as above.

## Tests

```sh
cd chrome && node --test test        # logic
chrome/bin/dev bundle exec rspec     # Ruby and browser specs, in Docker (the first build takes a few minutes)
```
