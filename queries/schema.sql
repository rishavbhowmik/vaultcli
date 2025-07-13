-- =========  1. vault-wide key envelope  ====================
CREATE TABLE vault_key (
    id INTEGER PRIMARY KEY CHECK (id = 1),
    wrapped_enc_key BLOB NOT NULL,
    -- password to encrypt the enc_key
    pass_hash BLOB NOT NULL,
    pass_hash_salt BLOB NOT NULL,
    pass_hash_iter INTEGER NOT NULL,
    -- Key Derivation Function params to encrypt the enc_key
    kdf TEXT NOT NULL,
    kdf_iters INTEGER NOT NULL,
    tag BLOB NOT NULL
);

-- =========  2. logical file / note index  =================
CREATE TABLE item (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    parent_id INTEGER REFERENCES item (id) ON DELETE CASCADE,
    name_hash TEXT NOT NULL, -- SHA-256(name)
    name_enc BLOB NOT NULL, -- encrypted name
    ctime INTEGER NOT NULL, -- epoch seconds
    mtime INTEGER NOT NULL
);

CREATE UNIQUE INDEX idx_item_namehash ON item (name_hash);

-- =========  3. encrypted payloads (versioned)  ============
CREATE TABLE blob(
    item_id INTEGER NOT NULL REFERENCES item (id) ON DELETE CASCADE,
    ver INTEGER NOT NULL,
    cipher_algo TEXT NOT NULL,
    nonce BLOB NOT NULL,
    tag BLOB NOT NULL,
    data BLOB NOT NULL,
    PRIMARY KEY (item_id, ver)
);
