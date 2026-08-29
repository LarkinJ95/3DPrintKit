ALTER TABLE users ADD COLUMN plan TEXT NOT NULL DEFAULT 'free';
ALTER TABLE users ADD COLUMN entitlement_status TEXT NOT NULL DEFAULT 'none';
ALTER TABLE users ADD COLUMN entitlement_source TEXT;
ALTER TABLE users ADD COLUMN subscription_expires_at TEXT;
ALTER TABLE users ADD COLUMN lifetime_access INTEGER NOT NULL DEFAULT 0;
ALTER TABLE users ADD COLUMN last_verified_at TEXT;
ALTER TABLE users ADD COLUMN app_account_token TEXT;

CREATE INDEX idx_users_app_account_token ON users(app_account_token);
CREATE INDEX idx_users_entitlement_expiry ON users(subscription_expires_at)
  WHERE lifetime_access = 0 AND plan = 'pro';

CREATE TABLE app_store_transactions (
  original_transaction_id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES users(id),
  product_id TEXT NOT NULL,
  kind TEXT NOT NULL,
  status TEXT NOT NULL,
  expires_at TEXT,
  environment TEXT NOT NULL,
  latest_signed_date TEXT NOT NULL,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX idx_app_store_transactions_user ON app_store_transactions(user_id);
