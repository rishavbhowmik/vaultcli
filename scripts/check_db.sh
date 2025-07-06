#!/usr/bin/env bash

DB_PATH="$1"
# Checks:
#   - File exists?
#   - Has all 3 main tables?
#   - Has at least one row in vault_key table?
if [[ ! -f "$DB_PATH" ]]; then
    exit 1
fi

TABLES=$(sqlite3 "$DB_PATH" ".tables")
if ! grep -q "vault_key" <<<"$TABLES"; then
    exit 1
fi
if ! grep -q "item" <<<"$TABLES"; then
    exit 1
fi
if ! grep -q "blob" <<<"$TABLES"; then
    exit 1
fi
COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM vault_key WHERE id=1;")
if [[ "$COUNT" -eq 0 ]]; then
    exit 1
fi

exit 0
