# VozLocal for Chrome

A new tab page that shows a Rioplatense Spanish phrase, then its translation, like `voz` in the terminal. It's laid out like Google Translate, and it shares learned phrases and your WhatsApp phrases with the terminal.

<p align="center"><img src="../assets/chrome-demo.gif" width="720" alt="The new tab: a Spanish phrase, a countdown, then its English meaning; it's marked learned, the next phrase follows, and the languages are swapped" /></p>

## Install

1. Open `chrome://extensions` and turn on **Developer mode**.
2. Click **Load unpacked** and choose the `chrome/extension` folder.
3. Open a new tab. Chrome asks once whether to keep the change; keep it.
4. To see it when Chrome starts as well: Settings › On startup › **Open the New Tab page**.

After pulling changes, click the reload arrow on the extension's card.

## Sharing with the terminal

With the [terminal plugin](../terminal/README.md) installed, run this once:

```sh
voz install-chrome
```

From then on, both read the same files:
- **Learned phrases:** `~/.cache/vozlocal/learned`. A phrase you `yas` in the terminal doesn't show in the next tab, and ✓ in Chrome adds to the same file.
- **Your phrases:** `terminal/data/<region>/mine.psv`, which `voz sync` fills from the WhatsApp bot. Run `voz install-cron` to sync every 2 minutes even when no terminal is open.

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
| Space | click the right panel | Reveal now; once revealed, the next phrase. After you Tab to a button, Space presses that button instead |
| N | → | Next phrase |
| L | ✓ | Mark as learned, so it isn't picked again; press again to undo |
| S | ⇄ | Swap the languages, so the English comes first |

It never shows a learned phrase. Once every phrase in today's category is learned, it moves to the next category that still has unlearned ones, and the chip shows which. Your WhatsApp phrases join whichever category is showing. It doesn't repeat the last phrase while anything else is left, and once everything is learned it says so.

## Layout

```
chrome/
├── extension/                the extension Chrome loads
│   ├── manifest.json         Manifest V3; its key fixes the extension's id
│   ├── newtab.{html,css,js}  the page; styles copy Google Translate's
│   ├── lib/voz.js            picks the day's category and phrase, cleans stored settings,
│   │                         reads the terminal host's replies; no DOM, so it's tested in Node
│   ├── data/phrases.json     terminal/data as JSON, made by bin/build-data; don't edit by hand
│   ├── fonts/                Google Sans (SIL Open Font License)
│   └── icons/                made by bin/build-icons
├── bin/
│   ├── build-data            rebuilds phrases.json; --check fails if it's out of date
│   ├── build-gifs            records the README's GIFs: the real new tab, and the WhatsApp chat
│   ├── whatsapp-demo.html    the phone build-gifs draws the chat on
│   ├── build-icons           renders assets/logo.svg as the extension's icons, in Chromium
│   └── dev                   runs a command in the Docker image (Ruby 3.4, Node, ffmpeg,
│                             Playwright's Chromium), so nothing uses the system Ruby
├── test/                     Node tests for voz.js
└── spec/                     RSpec specs, including Playwright specs that load the extension
```

## Phrases

Both apps read the same phrases. The shipped ones live in `terminal/data`, and the extension carries a copy in `phrases.json`. After changing a shipped `.psv` file, run:

```sh
chrome/bin/dev bin/build-data
```

A spec fails if you forget. Your own phrases (`mine.psv`) aren't copied: the extension reads them from the terminal, as above.

## Tests

```sh
cd chrome
node --test                  # logic
bin/dev bundle exec rspec    # Ruby and browser specs, in Docker (the first build takes a few minutes)
```
