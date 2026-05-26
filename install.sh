#!/usr/bin/env bash
# ============================================================================
# Demiton installer for Claude Desktop (macOS / Linux)
#
# Adds Demiton to Claude Desktop as an MCP connector via the mcp-remote
# bridge. Run once, then quit and reopen Claude Desktop. The Demiton
# connector appears in the chat interface; click Connect, log in once,
# and ask questions like "What contracts has Fulton Hogan won?".
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/demitonapp/claude-desktop-installer/main/install.sh | bash
#
# Or download and run directly:
#   bash install.sh                  # installs production (api.demiton.io)
#   bash install.sh --staging        # installs staging
#   bash install.sh --uninstall      # removes the Demiton entry
# ============================================================================

set -euo pipefail

# ---- Configuration ----------------------------------------------------------
SERVER_NAME="demiton"
PROD_URL="https://api.demiton.io/mcp/"
STAGING_URL="https://api-staging.demiton.io/mcp/"

# ---- Argument parsing -------------------------------------------------------
MODE="install"
TARGET_URL="$PROD_URL"
ENV_LABEL="production"

for arg in "$@"; do
    case "$arg" in
        --staging)
            TARGET_URL="$STAGING_URL"
            ENV_LABEL="staging"
            ;;
        --uninstall)
            MODE="uninstall"
            ;;
        --help|-h)
            sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "Unknown argument: $arg" >&2
            echo "Run with --help for usage." >&2
            exit 1
            ;;
    esac
done

# ---- Platform detection -----------------------------------------------------
PLATFORM="$(uname -s)"
case "$PLATFORM" in
    Darwin)
        CONFIG_DIR="$HOME/Library/Application Support/Claude"
        ;;
    Linux)
        CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/Claude"
        ;;
    *)
        echo "Unsupported platform: $PLATFORM" >&2
        echo "This installer supports macOS and Linux. Use install.ps1 on Windows." >&2
        exit 1
        ;;
esac

CONFIG_FILE="$CONFIG_DIR/claude_desktop_config.json"

# ---- Colour helpers (no-op when not a TTY) ---------------------------------
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    BOLD=$'\033[1m'; DIM=$'\033[2m'; RED=$'\033[31m'; GREEN=$'\033[32m'
    YELLOW=$'\033[33m'; BLUE=$'\033[34m'; RESET=$'\033[0m'
else
    BOLD=""; DIM=""; RED=""; GREEN=""; YELLOW=""; BLUE=""; RESET=""
fi

say()   { printf '%s\n' "$*"; }
info()  { printf '%s==>%s %s\n' "$BLUE" "$RESET" "$*"; }
ok()    { printf '%s%s%s\n' "$GREEN" "$*" "$RESET"; }
warn()  { printf '%s%s%s\n' "$YELLOW" "$*" "$RESET" >&2; }
fail()  { printf '%sError:%s %s\n' "$RED" "$RESET" "$*" >&2; exit 1; }

# ---- Banner -----------------------------------------------------------------
say ""
say "${BOLD}Demiton for Claude Desktop${RESET}"
say "${DIM}Setting up the ${ENV_LABEL} connector on ${PLATFORM}${RESET}"
say ""

# ---- Node.js requirement ----------------------------------------------------
ensure_node() {
    if command -v node >/dev/null 2>&1 && command -v npx >/dev/null 2>&1; then
        local node_version
        node_version="$(node --version 2>/dev/null || echo unknown)"
        info "Node.js detected (${node_version})"
        return 0
    fi

    warn "Node.js was not found. mcp-remote needs Node 18 or later to run."

    if [ "$PLATFORM" = "Darwin" ] && command -v brew >/dev/null 2>&1; then
        info "Installing Node.js via Homebrew..."
        brew install node
    elif command -v apt-get >/dev/null 2>&1; then
        info "Installing Node.js via apt..."
        sudo apt-get update -qq
        sudo apt-get install -y nodejs npm
    elif command -v dnf >/dev/null 2>&1; then
        info "Installing Node.js via dnf..."
        sudo dnf install -y nodejs npm
    else
        fail "Could not install Node.js automatically. Please install Node 18+ from https://nodejs.org and rerun this script."
    fi

    if ! command -v node >/dev/null 2>&1; then
        fail "Node.js install reported success but 'node' is still not on PATH. Open a new terminal and rerun this script."
    fi

    ok "Node.js installed: $(node --version)"
}

ensure_node

# ---- Config directory -------------------------------------------------------
info "Updating Claude Desktop config at ${CONFIG_FILE}"
mkdir -p "$CONFIG_DIR"

# Backup any existing config exactly once per run.
if [ -f "$CONFIG_FILE" ]; then
    BACKUP_FILE="${CONFIG_FILE}.demiton-backup-$(date +%Y%m%d%H%M%S)"
    cp "$CONFIG_FILE" "$BACKUP_FILE"
    say "${DIM}  Existing config backed up to: ${BACKUP_FILE}${RESET}"
fi

# ---- Merge entry via Node ---------------------------------------------------
# We use Node for JSON manipulation because it's guaranteed available at this
# point and handles preserving formatting / comments better than shell tools.
SERVER_NAME="$SERVER_NAME" \
TARGET_URL="$TARGET_URL" \
MODE="$MODE" \
CONFIG_FILE="$CONFIG_FILE" \
node <<'NODE_SCRIPT'
const fs = require('fs');
const path = require('path');

const file = process.env.CONFIG_FILE;
const name = process.env.SERVER_NAME;
const url  = process.env.TARGET_URL;
const mode = process.env.MODE;

// Read existing config, or start fresh.
let cfg = {};
if (fs.existsSync(file)) {
    const raw = fs.readFileSync(file, 'utf8').trim();
    if (raw.length > 0) {
        try {
            cfg = JSON.parse(raw);
        } catch (e) {
            console.error(`The existing config file is not valid JSON: ${e.message}`);
            console.error(`Fix it manually or delete it, then rerun.`);
            process.exit(1);
        }
    }
}

if (typeof cfg !== 'object' || cfg === null || Array.isArray(cfg)) {
    console.error('Existing config is not a JSON object. Aborting to avoid clobbering.');
    process.exit(1);
}

cfg.mcpServers = cfg.mcpServers || {};

if (mode === 'uninstall') {
    if (cfg.mcpServers[name]) {
        delete cfg.mcpServers[name];
        fs.writeFileSync(file, JSON.stringify(cfg, null, 2) + '\n');
        console.log(`Removed '${name}' entry from claude_desktop_config.json.`);
    } else {
        console.log(`No '${name}' entry found; nothing to remove.`);
    }
    process.exit(0);
}

// Install / update.
cfg.mcpServers[name] = {
    command: 'npx',
    args: ['-y', 'mcp-remote', url],
};

// Preserve other keys, write back with stable formatting.
fs.writeFileSync(file, JSON.stringify(cfg, null, 2) + '\n');
console.log(`Wrote '${name}' entry pointing at ${url}.`);
NODE_SCRIPT

# ---- Final instructions -----------------------------------------------------
say ""
if [ "$MODE" = "uninstall" ]; then
    ok "Demiton has been removed from Claude Desktop."
    say "Quit and reopen Claude Desktop for the change to take effect."
else
    ok "Demiton is installed."
    say ""
    say "${BOLD}Next steps:${RESET}"
    say "  1. Quit Claude Desktop completely (Cmd-Q on macOS)."
    say "  2. Reopen Claude Desktop."
    say "  3. Start a new chat and click the connector icon."
    say "  4. The first message that uses Demiton will open your browser to log in."
    say ""
    say "${DIM}Need help? Email support@demiton.io${RESET}"
fi
say ""

