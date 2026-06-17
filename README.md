# Vault0

Simple and secure way to manage your application secrets and configurations - your secrets deserve better than a `.env`.

## Supported Platforms

- [x] macOS

## Setup

1. Install the macOS app and complete onboarding (set master password)
2. Create vaults and environments, add your secrets
3. Install the CLI: `cd cli && cargo install --path .`

## CLI Usage

> **Note:** The macOS app must be installed and running for CLI commands to work.

### Open a shell with secrets loaded

```bash
vault0 shell
```

Opens a new shell with secrets as environment variables. Type `exit` to return to your original shell.

### Run a command with secrets

```bash
vault0 exec 'psql $DATABASE_URL'
vault0 exec 'npm run dev'
```

Note: Use single quotes to prevent variable expansion in your current shell.

### Import/Export

```bash
vault0 import .env          # Import from .env file
vault0 export .env.backup   # Export to .env file
```

### API Key Authentication

For CI/CD or automated environments. (Coming Soon)

## 1Password Integration (per environment)

An environment can be backed by 1Password instead of vault0's local storage. Its
secrets then live in a single 1Password item (one field per variable) and are
read/written through the 1Password CLI — nothing is stored in vault0's database
for that environment.

Prerequisites:

- Install the 1Password CLI (`op`): `brew install 1password-cli`
- Create a [1Password service account](https://developer.1password.com/docs/service-accounts/)
  and grant it access to the vault holding your secrets. Copy its token (`ops_...`).

Set it up (in the macOS app):

1. Open **Manage Environments** and click the key icon on the environment you
   want to back with 1Password.
2. Paste the service account token and click **Connect**.
3. Pick the 1Password **vault** and the **item** to store the variables in, then **Save**.

Any secrets already in that environment are pushed into the chosen item and the
local copies are removed. After this, `vault0 shell/exec/export` and the app's
secrets view work exactly as before — they read from 1Password transparently.
The token is stored in the macOS Keychain, never in the database.

Notes:

- The op CLI path defaults to `op` (resolved from `PATH`); change it in the app's
  Settings if needed.
- API keys are not available for 1Password-backed environments.

## Building the macOS App

Requires Xcode, Rust toolchain, and Ruby with Bundler.

```bash
# Install Ruby dependencies (first time only)
bundle install

# Initial setup: configure Xcode project and generate C header
bundle exec rake setup

# Build the release app
bundle exec rake release
```

The built app will be at:

```
build/release/Vault0.app
```

This task builds the Rust library in release mode, regenerates the C header, and runs `xcodebuild` against the `Vault0` scheme with the `Release` configuration.
