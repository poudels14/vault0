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
