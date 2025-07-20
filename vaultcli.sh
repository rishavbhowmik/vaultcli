BASEDIR=$(dirname "$0")
DB_PATH=""
MASTER_KEY=""

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
		*) usage ;;
		esac
	done
}

prompt_path() {
	if [ -n "$DB_PATH" ]; then return; fi
	action=$(gum choose "Select existing vault file" "Create new vault file")
	if [ "$action" = "Select existing vault file" ]; then
		if echo "$OSTYPE" | grep -q "darwin" && command -v osascript >/dev/null 2>&1; then
			DB_PATH=$(osascript -e 'POSIX path of (choose file with prompt "Select vault file:")')
		else
			echo "Navigate to your existing vault and press Enter:"
			DB_PATH=$(gum file "$PWD")
		fi
	else
		if echo "$OSTYPE" | grep -q "darwin" && command -v osascript >/dev/null 2>&1; then
			DB_PATH=$(osascript -e 'POSIX path of (choose file name with prompt "Create new vault file:")')
		else
			printf "New vault file path: "
			read DB_PATH
		fi
	fi
	if [ -z "$DB_PATH" ]; then
		echo "Error: path required." >&2
		exit 1
	fi
}

check_vault() {
	sh "$BASEDIR/scripts/check_db.sh" "$DB_PATH"
}

# Apple's built-in OpenSSL is too old and too limited. `openssl passwd -pbkdf2` is not supported. Looping with `openssl dgst -sha256` is an option in theory, but it's too slow (takes 5s for 1000 iterations on my M1 mac).
# So python3's hashlib is best option I got.
pbkdf2_sha256() {
	local pw="$1" salt="$2" iter="$3"
	python3 -c "import sys,hashlib,binascii; h=hashlib.pbkdf2_hmac('sha256', sys.argv[1].encode(), bytes.fromhex(sys.argv[2]), int(sys.argv[3])); print(binascii.hexlify(h).decode())" "$pw" "$salt" "$iter"
}

init_vault() {
	echo "=== Setup vault ==="
	prompt_path
	while :; do
		p1=$(gum input --password --placeholder "Master password")
		if [ -z "$p1" ]; then
			echo "Empty password."
			continue
		fi
		p2=$(gum input --password --placeholder "Confirm password")
		if [ "$p1" = "$p2" ]; then break; fi
		echo "Mismatch, try again."
	done

	enc_key=$(openssl rand -hex 32)

	pass_hash_salt=$(openssl rand -hex 32)
	pass_hash_iter=200000
	pass_hash=$(pbkdf2_sha256 "$p1" "$pass_hash_salt" "$pass_hash_iter")

	kdf_iters=200000
	wrapped_enc_key=$(echo "$enc_key" |
		openssl enc -aes-256-cbc -salt -a \
			-pbkdf2 -iter "$kdf_iters" \
			-pass pass:"$p1")

	sqlite3 "$DB_PATH" <"$BASEDIR/queries/schema.sql"
	sqlite3 "$DB_PATH" <<SQL
INSERT INTO vault_key (id, wrapped_enc_key, pass_hash, pass_hash_salt, pass_hash_iter, kdf, kdf_iters, tag)
VALUES (1, '$wrapped_enc_key', '$pass_hash', '$pass_hash_salt', $pass_hash_iter, 'openssl-aes-256-cbc', $kdf_iters, X'');
SQL

	echo "Vault ready: $DB_PATH"
}

load_vault_key() {
	echo "=== Unlock vault ==="
	result=$(sqlite3 "$DB_PATH" -separator '|' "SELECT replace(wrapped_enc_key, char(10), ''), kdf_iters, pass_hash, pass_hash_salt, pass_hash_iter FROM vault_key WHERE id=1;")
	IFS='|' read -r wrapped_key kdf_iters pass_hash pass_hash_salt pass_hash_iter <<<"$result"
	while :; do
		pass=$(gum input --password --placeholder "Enter master password")
		code=$?
		# Ctrl‑C or Esc exits gum with non‑zero status
		[ "$code" -ne 0 ] && echo "Aborted." && exit 130
		# Ctrl‑D returns empty string with status 0
		[ -z "$pass" ] && echo "Aborted." && exit 1

		input_pass_hash=$(pbkdf2_sha256 "$pass" "$pass_hash_salt" "$pass_hash_iter")
		if [ "$input_pass_hash" != "$pass_hash" ]; then
			echo "Invalid password, try again (Ctrl+C to quit)."
			continue
		fi

		key=$(
			echo "$wrapped_key" |
				openssl enc -d -aes-256-cbc -salt -a \
					-pbkdf2 -iter "$kdf_iters" \
					-pass pass:"$pass" 2>/dev/null
		)
		MASTER_KEY="$key"
		if [ -n "$MASTER_KEY" ]; then
			break
		fi
	done
}

change_vault_password() {
	echo "=== Change vault password ==="
	# Verify current password
	result=$(sqlite3 "$DB_PATH" -separator '|' "SELECT replace(wrapped_enc_key, char(10), ''), kdf_iters, pass_hash, pass_hash_salt, pass_hash_iter FROM vault_key WHERE id=1;")
	IFS='|' read -r wrapped_key kdf_iters pass_hash pass_hash_salt stored_iter <<<"$result"

	while :; do
		oldpassword=$(gum input --password --placeholder "Enter CURRENT master password")
		[ -z "$oldpassword" ] && echo "Aborted." && return 1
		input_pass_hash=$(pbkdf2_sha256 "$oldpassword" "$pass_hash_salt" "$stored_iter")
		if [ "$input_pass_hash" != "$pass_hash" ]; then
			echo "Invalid password, try again (Ctrl+C to quit)."
			sleep 1
			continue
		fi
		# Try to unwrap
		enc_key=$(echo "$wrapped_key" | openssl enc -d -aes-256-cbc -salt -a -pbkdf2 -iter "$kdf_iters" -pass pass:"$oldpassword" 2>/dev/null)
		if [ -z "$enc_key" ]; then
			echo "Failed to decrypt vault key. Aborted."
			return 1
		fi
		break
	done

	# Set new password
	while :; do
		p1=$(gum input --password --placeholder "New master password")
		[ -z "$p1" ] && echo "Empty password." && continue
		p2=$(gum input --password --placeholder "Confirm new password")
		[ "$p1" = "$p2" ] && break
		echo "Mismatch, try again."
	done

	# Step 3: Hash new password, rewrap enc_key
	new_salt=$(openssl rand -hex 16)
	new_iter=200000
	new_pass_hash=$(pbkdf2_sha256 "$p1" "$new_salt" "$new_iter")
	new_wrapped_key=$(echo "$enc_key" | openssl enc -aes-256-cbc -salt -a -pbkdf2 -iter "$kdf_iters" -pass pass:"$p1")

	# Step 4: Update DB
	sqlite3 "$DB_PATH" <<SQL
UPDATE vault_key
  SET pass_hash='$new_pass_hash',
      pass_hash_salt='$new_salt',
      pass_hash_iter=$new_iter,
      wrapped_enc_key='$new_wrapped_key'
WHERE id=1;
SQL

	echo "Vault password changed successfully."
}

main_menu() {
	while :; do
		cmd=$(
			gum choose \
				"Add note" \
				"Read note" \
				"List notes" \
				"Change password" \
				"Exit"
		)
		case "$cmd" in
		"Add note") echo "Add note" ;;
		"Read note") echo "Read note" ;;
		"List notes") echo "List notes" ;;
		"Change password") change_vault_password ;;
		"Exit") exit 0 ;;
		esac
	done
}

main() {
	parse_args "$@"
	prompt_path
	if check_vault; then
		load_vault_key
	else
		init_vault
		load_vault_key
	fi
	main_menu
}

main "$@"
