#!/usr/bin/env bash
set -euo pipefail

BASEDIR=$(dirname "$0")
DB_PATH=""

usage() {
  cat <<EOF
Usage: $(basename "$0") --file /path/to/vault.sqlite
Options:
  --file   Path to vault DB (created if missing)
EOF
  exit 1
}

parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      --file)
        DB_PATH="$2"
        shift 2
        ;;
      *)
        usage
        ;;
    esac
  done
}

prompt_path() {
  [[ -n "$DB_PATH" ]] && return
  action=$(gum choose "Select existing vault file" "Create new vault file")
  if [[ "$action" == "Select existing vault file" ]]; then
    echo "Navigate to your existing vault and press Enter:"
    DB_PATH=$(gum file "$PWD")
  else
    read -e -p "New vault file path: " DB_PATH
  fi
  [[ -n "$DB_PATH" ]] || { echo "Error: path required." >&2; exit 1; }
}

check_vault() {
  bash "$BASEDIR/scripts/check_db.sh" "$DB_PATH"
}

init_vault() {
  echo "=== Setup vault ==="
  prompt_path

  # Password
  while true; do
    p1=$(gum input --password --placeholder "Master password")
    [[ -n "$p1" ]] || { echo "Empty password."; continue; }
    p2=$(gum input --password --placeholder "Confirm password")
    [[ "$p1" == "$p2" ]] && break
    echo "Mismatch, try again."
  done

  # Generate key and salt (8 bytes -> 16 hex chars)
  key=$(openssl rand -hex 32)
  salt=$(openssl rand -hex 8)

  # Wrap key with password (use pbkdf2)
  wrapped=$(
    echo -n "$key" |
    openssl enc -aes-256-cbc -a -salt -pbkdf2 -iter 100000 \
      -S "$salt" -pass pass:"$p1"
  )

  # Init DB
  sqlite3 "$DB_PATH" < "$BASEDIR/queries/schema.sql"

  # Insert vault key (tag unused for CBC)
  sqlite3 "$DB_PATH" <<-SQL
    INSERT INTO vault_key (
      id, kdf, kdf_salt, kdf_iters,
      enc_algo, enc_key, tag
    ) VALUES (
      1, 'openssl-aes-256-cbc', X'$salt', 100000,
      'AES-256-CBC', '$wrapped', X''
    );
SQL

  echo "Vault ready: $DB_PATH"
}

main_menu() {
  while true; do
    cmd=$(gum choose \
      "Add note" \
      "Read note" \
      "List notes" \
      "Change password" \
      "Exit"
    )
    case "$cmd" in
      "Add note") echo "Add note";;
      "Read note") echo "Read note";;
      "List notes") echo "List notes";;
      "Change password") echo "Change password";;
      "Exit") exit 0;;
    esac
  done
}

main() {
  parse_args "$@"
  prompt_path

  if ! check_vault; then
    init_vault
  fi

  main_menu
}

main "$@"
