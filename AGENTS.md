# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Vault0 is a macOS secret management application with a CLI tool for loading secrets into shell environments. It consists of three main components:

1. **Rust Library (`lib/`)**: Core cryptography and database operations exposed via C FFI
2. **macOS App (`ui/mac/Vault0/`)**: SwiftUI-based menu bar application
3. **CLI Tool (`cli/`)**: Command-line interface for loading secrets into shell sessions

The app uses client-server architecture where the macOS app runs a Unix socket server (`~/.vault0/vault0.sock`) that the CLI connects to for fetching secrets.

## Build Commands

### Initial Setup
```bash
# Configure Xcode project and generate C headers
bundle exec rake setup
```

### Rust Library
```bash
# Build debug (faster, for development)
cd lib && cargo build

# Build release (optimized)
cd lib && cargo build --release

# Run tests
cd lib && cargo test

# Generate C header (required after changing FFI functions)
cd lib && cbindgen --config cbindgen.toml --crate vault0 --output vault0.h
```

### CLI Tool
```bash
# Build and install locally
cd cli && cargo install --path .

# This installs the `vault0` binary to ~/.cargo/bin
```

### macOS App
```bash
# Build debug Rust lib + generate header
bundle exec rake build:lib

# Build complete release app
bundle exec rake release

# The app will be at:
# ~/Library/Developer/Xcode/DerivedData/Vault0-*/Build/Products/Release/Vault0.app
```

### Code Formatting
```bash
# Format both Rust and Swift code
bundle exec rake format

# Or individually:
cd lib && cargo fmt          # Rust
cd ui/mac && swiftformat .   # Swift
```

### Clean Build Artifacts
```bash
bundle exec rake clean
```

## Architecture

### Cryptography Stack (Multi-Layer Encryption)

Vault0 uses a sophisticated multi-layered encryption approach:

1. **Master Password Layer**:
   - User enters master password during onboarding
   - Password is hashed with bcrypt for verification (stored in `master_passwords` table)
   - A random 32-byte secret key is generated and encrypted with a key derived from the password using Argon2id
   - Encrypted secret key is stored in macOS Keychain (not in database)

2. **Master Key Derivation**:
   - Master key = Argon2id(password, secret_key, salt)
   - This master key is held in memory (via `session.rs`) while the app is unlocked
   - Used to encrypt/decrypt vault-specific keys

3. **Per-Vault Encryption Keys**:
   - Each vault has its own random 32-byte encryption key (DEK - Data Encryption Key)
   - Vault DEK is encrypted with the master key and stored in `vault_encryption_keys` table
   - This allows different vaults to have independent encryption

4. **Secret Encryption**:
   - Individual secrets (keys and values) are encrypted with the vault's DEK using AES-256-GCM
   - Each encryption has a unique nonce stored alongside the ciphertext
   - Both the secret key and value are encrypted separately (two ciphertext + nonce pairs)

5. **API Keys & JWT**:
   - API keys are JWTs signed with ES256 (ECDSA P-256)
   - ECDSA private key is generated during onboarding and encrypted with secret code (same key derivation as secret key)
   - Encrypted ECDSA private key stored in Keychain
   - Public key stored in database for verification
   - Each API key JWT contains an embedded DEK for decrypting that vault's secrets without requiring the master password

**Why this architecture?**
- Master password compromise doesn't expose secrets directly (secret key needed from Keychain)
- Each vault can be independently encrypted/rotated
- API keys can access specific vaults without full access to master key
- Secrets never touch disk unencrypted

### FFI Bridge (Rust ↔ Swift)

The Rust library exposes C-compatible functions (prefixed with `vault0_`) that Swift calls:

- `lib/src/lib.rs`: FFI function definitions with `#[no_mangle]` and `extern "C"`
- `lib/vault0.h`: Auto-generated C header via cbindgen
- `ui/mac/Vault0/Services/Vault0Library.swift`: Swift wrapper around C functions

**Session Management:**
- `session.rs` maintains in-memory master key using thread-local storage
- Master key is automatically zeroized when cleared (via `zeroize` crate)
- Call `vault0_clear_session()` when locking the app

## Security Considerations

- Never log or print decrypted secrets, master keys, or DEKs
- Use `zeroize` for sensitive data in memory (already applied to `MasterKey` and `VaultKey`)
- Master password verification uses constant-time comparison (bcrypt)
- All crypto uses CSPRNG (`OsRng` from `rand` crate)
- API key JWTs embed a DEK, so treat API keys as sensitive
- Socket has no per-connection authentication currently (relies on filesystem permissions and app authentication gate)



## Coding styles
- dont write unnecessary comments and keep the code clean and organized
- dont use emojis

## Git
- dont add Co-Authored-By or any other AI attribution lines to commit messages or PR descriptions
