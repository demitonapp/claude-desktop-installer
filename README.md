# Demiton for Claude Desktop

One-line installer that adds Demiton to Claude Desktop as an MCP connector,
so you can ask Demiton questions directly in chat.

```
"What contracts has Fulton Hogan won in the last 12 months?"
"How many rain days in Gympie last wet season?"
"What's the P&L on the Caloundra Road job?"
```

## Install

### macOS

Open Terminal (Spotlight: `Terminal`) and paste:

```bash
curl -fsSL https://raw.githubusercontent.com/demitonapp/claude-desktop-installer/main/install.sh | bash
```

### Windows

Open PowerShell and paste:

```powershell
irm https://raw.githubusercontent.com/demitonapp/claude-desktop-installer/main/install.ps1 | iex
```

If PowerShell refuses to run downloaded scripts, run this instead:

```powershell
powershell -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/demitonapp/claude-desktop-installer/main/install.ps1 | iex"
```

### After install

1. Quit Claude Desktop completely (Cmd-Q on macOS, right-click the tray icon
   then Quit on Windows).
2. Reopen Claude Desktop.
3. Start a new chat. Demiton appears in the connector list.
4. The first message that uses Demiton opens your browser to log in.

## What the installer does

- Checks that Node.js 18+ is installed. If it's missing, installs it via
  Homebrew (macOS), `apt`/`dnf` (Linux), or `winget`/`choco` (Windows).
- Backs up your existing `claude_desktop_config.json` (timestamped copy
  alongside the original).
- Merges a single `demiton` entry into `mcpServers` without touching any
  other connector you have configured. The entry uses
  [`mcp-remote`](https://www.npmjs.com/package/mcp-remote) to bridge
  Claude Desktop's STDIO transport to Demiton's hosted HTTPS endpoint at
  `https://api.demiton.io/mcp`.
- Prints next steps.

The config file lives at:

| Platform | Path                                                       |
| -------- | ---------------------------------------------------------- |
| macOS    | `~/Library/Application Support/Claude/claude_desktop_config.json` |
| Windows  | `%APPDATA%\Claude\claude_desktop_config.json`              |
| Linux    | `${XDG_CONFIG_HOME:-~/.config}/Claude/claude_desktop_config.json` |

## Why a bridge instead of Claude Desktop's "custom connector" UI?

Claude Desktop's built-in "Add custom connector" flow currently has an
unresolved bug where OAuth completes but the bearer token is never
attached to subsequent requests (tracked in
[anthropics/claude-ai-mcp#155](https://github.com/anthropics/claude-ai-mcp/issues/155)
and several related issues). Until that's fixed, the `mcp-remote` STDIO
bridge is the reliable path.

When the upstream bug is resolved we will publish a one-line URL you can
paste into "Add custom connector" instead, and this installer becomes
optional.

## Uninstall

### macOS / Linux

```bash
curl -fsSL https://raw.githubusercontent.com/demitonapp/claude-desktop-installer/main/install.sh | bash -s -- --uninstall
```

### Windows

```powershell
irm https://raw.githubusercontent.com/demitonapp/claude-desktop-installer/main/install.ps1 | iex -ArgumentList '-Uninstall'
```

Or run the script with `--uninstall` (bash) / `-Uninstall` (PowerShell) if
you saved it locally.

The uninstaller removes only the `demiton` entry; every other MCP server in
your config is left in place.

## Staging

For internal testing against staging:

```bash
bash install.sh --staging
```

```powershell
.\install.ps1 -Staging
```

## What gets added to your config

```json
{
  "mcpServers": {
    "demiton": {
      "command": "npx",
      "args": ["-y", "mcp-remote", "https://api.demiton.io/mcp"]
    }
  }
}
```

If `mcpServers` already contains other entries, they are preserved untouched.

## Troubleshooting

**"Node.js install reported success but `node` is still not on PATH."**
Open a new terminal window (or sign out and back in on Windows) and rerun
the installer. `winget` and `brew` install Node to a path that isn't
visible to the current shell session.

**"The existing config file is not valid JSON."**
Your `claude_desktop_config.json` has hand-edited syntax errors. The
installer refuses to overwrite it to avoid losing your other server
entries. Open the file, fix the JSON, and rerun.

**Claude Desktop doesn't show Demiton after restart.**
Make sure you fully quit Claude Desktop (not just close the window). On
macOS use Cmd-Q; on Windows right-click the tray icon and choose Quit.

**OAuth browser tab doesn't redirect back to localhost.**
This is usually a firewall or VPN intercepting the loopback callback. Try
again with the VPN off, or contact support@demiton.io.

## Security

- The installer never asks for your Demiton credentials. Authentication
  happens in your browser the first time you use Demiton in a chat, using
  Demiton's OAuth 2.1 server.
- `mcp-remote` stores its OAuth tokens in `~/.mcp-auth/` (macOS/Linux) or
  `%USERPROFILE%\.mcp-auth\` (Windows). Delete that folder to force a
  re-login.
- The installer makes a timestamped backup of your existing config before
  every change. To revert manually, copy the backup file back over
  `claude_desktop_config.json`.

## License

MIT.
