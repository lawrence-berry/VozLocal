-- Confirmed phrases. voz sync pulls rows with id greater than the last one it saw.
CREATE TABLE phrases (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  phrase TEXT NOT NULL UNIQUE,
  translation TEXT NOT NULL,
  created_at INTEGER NOT NULL
);

-- The phrase waiting for a yes, one per sender.
CREATE TABLE pending (
  sender TEXT PRIMARY KEY,
  phrase TEXT NOT NULL,
  translation TEXT NOT NULL,
  created_at INTEGER NOT NULL
);

-- WhatsApp message ids already handled. Meta retries webhooks, so each message is acted on once.
CREATE TABLE seen (
  message_id TEXT PRIMARY KEY,
  created_at INTEGER NOT NULL
);
