# vault0 CLI

A command-line interface for loading and managing secrets from your vault0 secret management system.

## Installation

### 1. Install the CLI Binary

```bash
cargo install --path .
```

This will install the `vault0` binary to your `~/.cargo/bin` directory.

### 2. Set Up Shell Integration (Recommended)

For the best experience, install the shell integration so you can use `vault0 load` and `vault0 unload` directly without `eval`:

**For Bash/Zsh:**
```bash
cd shell
bash install.sh
source ~/.bashrc  # or source ~/.zshrc
```

Or manually add to your `~/.bashrc` or `~/.zshrc`:
```bash
source /path/to/vault0/cli/shell/vault0.sh
```

**For Fish:**
Add to your `~/.config/fish/config.fish`:
```fish
source /path/to/vault0/cli/shell/vault0.fish
```

## Prerequisites

- You must have the vault0 macOS app **running and logged in**
- The app acts as a server that the CLI connects to via Unix socket
- At least one vault with secrets configured in the app

## Usage

### Load Secrets

**With Shell Integration (Recommended):**

```bash
vault0 load <vault-name> <environment>
```

**Without Shell Integration:**

```bash
eval $(vault0 load <vault-name> <environment>)
```

**Examples:**

```bash
# Load development secrets from the "default" vault
vault0 load default development

# Load production secrets from a custom vault
vault0 load myapp production
```

When you run this command:
1. The CLI connects to the vault0 macOS app via Unix socket (`~/.vault0/vault0.sock`)
2. The app (already authenticated) fetches and decrypts the requested secrets
3. Each secret is exported as an environment variable
4. A `VAULT0_SHELL_STATUS` environment variable is set to track which variables were loaded

### Unload Secrets

Remove previously loaded secrets from your shell environment:

**With Shell Integration (Recommended):**

```bash
vault0 unload
```

**Without Shell Integration:**

```bash
eval $(vault0 unload)
```

This will:
1. Read the `VAULT0_SHELL_STATUS` environment variable to see which variables were loaded
2. Unset all those environment variables
3. Unset the `VAULT0_SHELL_STATUS` variable itself

### Help

View available commands:

```bash
vault0 --help
vault0 load --help
vault0 unload --help
```

## How It Works

### Shell Integration

Since a child process cannot modify the parent shell's environment, the CLI outputs shell commands that you execute using `eval`.

- `vault0 load` outputs `export KEY='value'` commands
- `vault0 unload` outputs `unset KEY` commands

### State Tracking

The CLI maintains state in a `VAULT0_SHELL_STATUS` environment variable that contains JSON with:
- Which vault was loaded
- Which environment was used
- The list of variable names that were exported

This allows the `unload` command to know exactly which variables to unset. Each shell session maintains its own state, so you can have different vaults loaded in different terminal windows.

### Security

- Your master password is required for each `load` operation
- The password is entered securely (not echoed to terminal)
- Secrets are decrypted using the existing vault0-lib cryptography
- The `VAULT0_SHELL_STATUS` variable only stores variable names, not secret values
- Secret values are only stored in the shell's environment variables (standard shell behavior)
- The CLI uses the same multi-layered encryption as the macOS app

## Architecture

The CLI uses a **client-server architecture** over Unix domain sockets:

```
┌─────────────┐         Unix Socket        ┌──────────────────┐
│   CLI       │◄──────────────────────────►│   macOS App      │
│  (Client)   │   ~/.vault0/vault0.sock   │   (Server)       │
│             │                             │                  │
│  - Connects │                             │ - Authenticated  │
│  - Requests │                             │ - Decrypts       │
│  - Exports  │                             │ - Serves         │
└─────────────┘                             └──────────────────┘
```

**Benefits:**
- No password entry needed in CLI (app is already authenticated)
- Secrets never touch disk unencrypted
- Single source of truth (the macOS app)
- App controls all access to secrets

**Protocol:**
- JSON over Unix socket
- See `SOCKET_PROTOCOL.md` for details

## Troubleshooting

**"Failed to connect to vault0 server"**
- Make sure the vault0 macOS app is running
- Ensure you're logged in to the app (entered your master password)
- Check if the socket exists: `ls -la ~/.vault0/vault0.sock`

**"Server error: Not authenticated"**
- The app is running but you're not logged in
- Open the app and enter your master password

**"Vault 'xyz' not found"**
- Check that the vault name is correct (vault names cannot contain spaces)
- List your vaults in the macOS app to see available vault names

**"No secrets found for vault"**
- Verify the environment name is correct (e.g., "development", "production")
- Check that secrets exist for that vault and environment in the macOS app

## Examples

### Basic Workflow

**With Shell Integration:**

```bash
# Load secrets
vault0 load myapp development

# Now use the secrets in your environment
echo $DATABASE_URL
echo $API_KEY

# When done, unload them
vault0 unload
```

**Without Shell Integration:**

```bash
# Load secrets
eval $(vault0 load myapp development)

# Use secrets...

# Unload
eval $(vault0 unload)
```

### Per-Project Shell Scripts

**With Shell Integration:**

Create a `.vault0rc` script in your project:

```bash
#!/bin/bash
vault0 load myproject development
```

Then source it:

```bash
source .vault0rc
```

**Without Shell Integration:**

Create a `.env.sh` script:

```bash
#!/bin/bash
eval $(vault0 load myproject development)
```

Then source it:

```bash
source .env.sh
```

### Using with Different Shells

Shell integration is provided for:
- **Bash**: Use `shell/vault0.sh`
- **Zsh**: Use `shell/vault0.sh` (same as bash)
- **Fish**: Use `shell/vault0.fish`

Without shell integration, the CLI outputs POSIX-compatible commands that work with bash, zsh, and sh. For fish, use the provided shell integration file.

## Development

Build the project:

```bash
cargo build
```

Run tests:

```bash
cargo test
```

Install locally:

```bash
cargo install --path .
```
