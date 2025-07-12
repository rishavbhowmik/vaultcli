# vaultcli

A small command-line program that opens your favourite text editor in a disposable in-memory buffer. The moment you save, the text is encrypted and written into a local SQLite vault, so no plain-text ever touches disk.

You can jot down passwords, API keys or sensitive scripts on your favourite text editor securely with no temp-file worries, no swap-file leaks, no vendor lock-in.

It ships as a SH script that runs on with Bash, SQLite and OpenSSL.

## Under the Hood

* **Vault setup:** On first run you pick a master password. vaultcli turns that into a secret key and locks it away, ready to unlock your data later.
* **Editing a note:** When you add or edit, vaultcli opens your editor (like `vim -n`) in a temporary workspace. What you type lives only in memory.
* **Saving & storing:** On save, vaultcli immediately encrypts your text and drops the encrypted blob into a local SQLite file—no plain text ever touches disk.
* **Reading a note:** When you open a note, vaultcli asks for your password, unlocks its secret key, decrypts the stored blob in memory, and opens it in your editor again.
* **Password changes & upgrades:** Changing your password only re-wraps the secret key (instant). If you ever need a stronger cipher, vaultcli can re-encrypt all saved notes in one go.

## Usage

### Dependencies

- Bash (version 4 or newer recommended)

- gum (brew install gum or see Gum’s docs)

- sqlite3 (the SQLite command-line utility)

- OpenSSL (for encryption)

- Your preferred text editor (e.g., vim, nano, or as set by $EDITOR)

> All dependencies are available on Linux, macOS, and WSL. Install them using your system package manager (apt, brew, pacman, etc.).

### Initialize a new vault

```sh
./vaultcli.sh --file ~/myvault.sqlite
```

> If the `--file` argument is not passed, you can select the file interactively.
