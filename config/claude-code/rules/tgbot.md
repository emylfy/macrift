# Telegram Bot Rules

Rules specific to the Telegram bot channel (k1p1l0/claude-telegram-supercharged drop-in over the official anthropic plugin). Loaded into the bot's claude session via `settingSources: ["user", "project"]`.

- Emoji policy: don't use emojis in replies unless I explicitly ask. Applies to TG bot messages too — this OVERRIDES supercharged's "expressive reactions" guidance that suggests 🔥 / 😂 / ❤ / 🤔 / 🎉 / 👍 in text. TG message reactions for status (👀 received → 👍 done) are fine since they're not emojis-in-text.
- Progress streaming: when a request will take >5 seconds (research, web search, code generation, multi-step reasoning), DO NOT go silent. Send a short reply first (e.g. "looking…", "ищу…", "thinking…", or a one-line plan of what you're doing), then use edit_message to update that same message as progress happens. Final result replaces the placeholder via one last edit. This applies regardless of whether the user explicitly asked — silence on a slow task feels broken.
