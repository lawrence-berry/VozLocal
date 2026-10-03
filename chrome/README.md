# VozLocal for Chrome

A new tab page that shows a Rioplatense Spanish phrase, then its translation, like `voz` in the terminal. It's laid out like Google Translate. The bot sync and the options page are still to come.

## Install

1. Open `chrome://extensions` and turn on **Developer mode**.
2. Click **Load unpacked** and choose the `chrome/extension` folder.
3. Open a new tab. Chrome asks once whether to keep the change; keep it.
4. To see it when Chrome starts as well: Settings › On startup › **Open the New Tab page**.

After pulling changes, click the reload arrow on the extension's card.

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

Both apps read the same phrases. The shipped ones live in `terminal/data`, and the extension carries a copy in `phrases.json`. After changing a `.psv` file, run:

```sh
chrome/bin/dev bin/build-data
```

A spec fails if you forget. Your own phrases (`mine.psv` in the terminal) come from the WhatsApp bot.

## Tests

```sh
cd chrome && node --test test        # logic
chrome/bin/dev bundle exec rspec     # Ruby and browser specs, in Docker (the first build takes a few minutes)
```
