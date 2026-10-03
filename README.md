<p align="center">
  <img src="assets/logo.svg" width="128" height="128" alt="VozLocal logo: a speech bubble with a terminal prompt and the Argentine Sol de Mayo" />
</p>

<h1 align="center">VozLocal</h1>

<p align="center">
  <strong>Learn the Spanish Porteños actually speak, one terminal at a time.</strong><br />
  🇦🇷 Rioplatense Spanish, straight from the streets of Buenos Aires
</p>

<p align="center">
  <img src="https://img.shields.io/badge/zsh-5.0%2B-F15A24?style=for-the-badge&logo=zsh&logoColor=white" alt="zsh 5.0 or newer" />
  <img src="https://img.shields.io/badge/Chrome-MV3-4285F4?style=for-the-badge&logo=googlechrome&logoColor=white" alt="Chrome extension, Manifest V3" />
  <img src="https://img.shields.io/badge/Cloudflare-Workers-F38020?style=for-the-badge&logo=cloudflare&logoColor=white" alt="Cloudflare Workers" />
  <img src="https://img.shields.io/badge/Espa%C3%B1ol-Rioplatense-74ACDF?style=for-the-badge" alt="Rioplatense Spanish" />
</p>

<p align="center">
  <img src="assets/demo.svg" width="720" alt="VozLocal in a terminal: the phrase 'Qué quilombo' appears, a row of dots counts down, then the translation 'What a mess' is revealed" />
</p>

Textbook Spanish won't help when someone in Buenos Aires says *"Che, ¿vos querés ir al bondi o caminamos?"* VozLocal teaches the slang (*lunfardo*), the *vos* verb forms and the everyday expressions by repetition. It shows them where you already spend your day. A phrase appears, you get a moment to recall its meaning, and then the translation is revealed. There's no app to open and no streak to keep.

## Three parts, one set of phrases

| Part | What it does | Built with |
|---|---|---|
| [**Terminal**](terminal/README.md) | A phrase when you open a terminal, with `voz` for another and `yas` to mark one as learned | zsh |
| [**Chrome new tab**](chrome/README.md) | The same phrases in every new tab, laid out like Google Translate | Manifest V3 extension, native messaging |
| [**WhatsApp bot**](bot/README.md) | Text `Bondi = Bus` to your bot, reply `yes`, and the phrase joins your rotation | Cloudflare Worker, D1, WhatsApp Cloud API |

```mermaid
flowchart LR
  WA["WhatsApp<br/>Bondi = Bus"] --> Bot["Cloudflare Worker<br/>+ D1"]
  Bot -- "voz sync<br/>(shell start, cron)" --> Files[("terminal files<br/>phrases · learned · mine.psv")]
  Term["Terminal<br/>voz · yas"] <--> Files
  Chrome["Chrome new tab"] <-- "native messaging" --> Files
```

The terminal's files are the single source of truth. Mark a phrase as learned in either place and it stops appearing in both. Phrases from WhatsApp reach the terminal and Chrome within two minutes.

## Quick start

```sh
git clone https://github.com/lawrence-berry/VozLocal.git ~/VozLocal
echo 'source ~/VozLocal/terminal/vozlocal.plugin.zsh' >> ~/.zshrc
```

Open a new terminal. To add the Chrome extension, see [chrome/README.md](chrome/README.md). The bot is optional and self-hosted; see [bot/README.md](bot/README.md).

## Engineering highlights

- **Safe inside your shell.** The plugin is sourced into your interactive zsh, so your options and aliases can't change its behaviour. It checks every setting before arithmetic evaluation, and handles Ctrl-C cleanly.
- **Untrusted input handled carefully.**
  - The bot verifies Meta's HMAC signature over the raw request bytes.
  - It answers only allowed numbers, and handles each message once despite webhook retries.
  - Synced rows with control, bidi or zero-width characters, or invalid UTF-8, are dropped on both clients.
- **A browser talking to local files.** Chrome extensions can't read disk, so a small zsh program speaks Chrome's native messaging protocol: length-prefixed JSON on stdin and stdout. It shares a file lock with the terminal.
- **Resilient sync.**
  - Marks made while Chrome can't reach the terminal are queued and replayed.
  - A new tab never waits more than 0.4 s for the terminal.
  - A cron job keeps phrases flowing when no terminal is open.
- **No secrets in a public repo.** Tokens live in `~/.secrets` and Cloudflare, and examples use reserved, fictional numbers.

## Tests

| Part | Command | Checks |
|---|---|---|
| Terminal | `zsh terminal/tests/run.zsh` | 88, in plain zsh, including real pseudo-terminal shells |
| Bot | `node --test bot/test` | 19, against Node's built-in SQLite with the real migration |
| Chrome logic | `cd chrome && node --test test` | 21 |
| Chrome in the browser | `chrome/bin/dev bundle exec rspec` | 32 RSpec and Playwright specs that load the real extension and its native host in Chromium, in Docker |

## Roadmap

- ** Speach mode? **

<p align="center">
  <img src="assets/logo.svg" width="40" height="40" alt="" /><br />
  <em>¡Dale, a practicar!</em> 🇦🇷
</p>
