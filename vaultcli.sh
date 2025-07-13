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
	pass_hash=$(echo "$p1" | openssl dgst -sha256 | cut -d'=' -f2 | tr -d ' ')
	key=$(openssl rand -hex 32)
	wrapped=$(echo "$key" |
		openssl enc -aes-256-cbc -salt -a \
			-pbkdf2 -iter 200000 \
			-pass pass:"$p1")

	sqlite3 "$DB_PATH" <"$BASEDIR/queries/schema.sql"
	sqlite3 "$DB_PATH" <<SQL
INSERT INTO vault_key (id,kdf,kdf_iters,enc_algo,enc_key,password_hash,tag)
VALUES (1,'openssl-aes-256-cbc',200000,'AES-256-CBC','$wrapped','$pass_hash',X'');
SQL
	echo "Vault ready: $DB_PATH"
}

load_vault_key() {
	echo
	echo "=== Unlock vault ==="
	result="$(sqlite3 "$DB_PATH" -separator '|' "SELECT replace(enc_key, char(10), ''), kdf_iters, password_hash FROM vault_key WHERE id=1;")"
	IFS='|' read -r wrapped_key kdf_iters stored_pass_hash <<<"$result"
	while :; do
		pass=$(gum input --password --placeholder "Enter master password")
		code=$?
		# Ctrl‑C or Esc exits gum with non‑zero status
		[ "$code" -ne 0 ] && echo "Aborted." && exit 130
		# Ctrl‑D returns empty string with status 0
		[ -z "$pass" ] && echo "Aborted." && exit 1

		input_pass_hash=$(echo "$pass" | openssl dgst -sha256 | cut -d'=' -f2 | tr -d ' ')
		if [ "$input_pass_hash" != "$stored_pass_hash" ]; then
			echo "Invalid password, try again (Ctrl+C to quit)."
			continue
		fi

		key=$(
			echo "$wrapped_key" |
				openssl enc -d -aes-256-cbc -salt -a \
					-pbkdf2 -iter 200000 \
					-pass pass:"$pass" 2>/dev/null
		)
		MASTER_KEY="$key"
		if [ -n "$MASTER_KEY" ]; then
			break
		fi
	done
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
		"Change password") echo "Change password" ;;
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
