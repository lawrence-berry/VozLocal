# VozLocal for Chrome

A new tab page that shows a Rioplatense Spanish phrase, then its translation, like `voz` in the terminal. It's a work in progress: this folder has the phrase data and the page's logic so far, with the page itself still to come.

## Layout

| Path | What |
|---|---|
| `extension/` | The extension Chrome loads |
| `extension/lib/voz.js` | Picking the day's category and phrase, and reading the bot's `/phrases` rows. No DOM, so it's tested in Node |
| `extension/data/phrases.json` | `terminal/data` bundled as JSON, made by `bin/build-data`. Don't edit it by hand |
| `bin/build-data` | Rebuilds `phrases.json`. `--check` fails if it's out of date |
| `bin/dev` | Runs a command in the Docker image (Ruby 3.4), so nothing uses the system Ruby |
| `test/` | Node tests for `voz.js` |
| `spec/` | RSpec specs |

## Phrases

Both apps read the same phrases. The shipped ones live in `terminal/data`, and the extension carries a copy in `phrases.json`. After changing a `.psv` file, run:

```sh
chrome/bin/dev bin/build-data
```

A spec fails if you forget. Your own phrases (`mine.psv` in the terminal) come from the WhatsApp bot.

## Tests

```sh
cd chrome && node --test test        # logic
chrome/bin/dev bundle exec rspec     # Ruby specs, in Docker
```
