#!/usr/bin/env bash
set -euo pipefail

# ─── colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}${BOLD}→${RESET} $*"; }
success() { echo -e "${GREEN}${BOLD}✓${RESET} $*"; }
warn()    { echo -e "${YELLOW}${BOLD}!${RESET} $*"; }
error()   { echo -e "${RED}${BOLD}✗${RESET} $*" >&2; exit 1; }
ask()     { echo -e "${BOLD}$*${RESET}"; }

# ─── checks ───────────────────────────────────────────────────────────────────
command -v wrangler >/dev/null 2>&1 || error "wrangler not found — run: npm install -g wrangler"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo ""
echo -e "${BOLD}Akira GitHub Proxy — Production Setup${RESET}"
echo "────────────────────────────────────────"
echo ""
echo "You'll need: GitHub App Client ID and Client Secret"
echo "(GitHub → Settings → Developer settings → GitHub Apps → your app)"
echo ""

# ─── 1. GitHub App Slug ───────────────────────────────────────────────────────
ask "1. GitHub App slug (the name in the install URL, e.g. 'my-akira-app'):"
read -r GITHUB_APP_SLUG
[[ -n "$GITHUB_APP_SLUG" ]] || error "App slug cannot be empty"

# ─── 2. Client ID ─────────────────────────────────────────────────────────────
ask "2. GitHub App Client ID (starts with Iv1.):"
read -r GITHUB_CLIENT_ID
[[ -n "$GITHUB_CLIENT_ID" ]] || error "Client ID cannot be empty"

# ─── 3. Client Secret ─────────────────────────────────────────────────────────
ask "3. GitHub App Client Secret:"
read -rs GITHUB_CLIENT_SECRET
echo ""
[[ -n "$GITHUB_CLIENT_SECRET" ]] || error "Client Secret cannot be empty"

# ─── 4. npm install ───────────────────────────────────────────────────────────
echo ""
info "Installing worker dependencies..."
npm install --silent
success "Dependencies installed"

# ─── 6. Push secrets to Cloudflare ───────────────────────────────────────────
echo ""
info "Pushing secrets to Cloudflare Workers..."

echo "$GITHUB_CLIENT_ID"     | wrangler secret put GITHUB_CLIENT_ID     --name akira-github-proxy
echo "$GITHUB_CLIENT_SECRET" | wrangler secret put GITHUB_CLIENT_SECRET --name akira-github-proxy

success "Secrets stored"

# ─── 7. Deploy ────────────────────────────────────────────────────────────────
echo ""
info "Deploying worker..."
DEPLOY_OUTPUT="$(wrangler deploy 2>&1)"
echo "$DEPLOY_OUTPUT"

WORKER_URL="$(echo "$DEPLOY_OUTPUT" | grep -oE 'https://[a-z0-9._-]+\.workers\.dev' | head -1)"
[[ -n "$WORKER_URL" ]] || error "Could not extract worker URL from deploy output"

success "Worker deployed at: ${BOLD}${WORKER_URL}${RESET}"

# ─── 8. Smoke test ────────────────────────────────────────────────────────────
echo ""
info "Running smoke test (checking authentication works)..."
HTTP_STATUS="$(curl -s -o /dev/null -w "%{http_code}" \
  -X POST "${WORKER_URL}/github/connect" \
  -H "Content-Type: application/json" \
  -H "X-Akira-Secret: ${AKIRA_SECRET}" \
  -d '{"code": "smoke_test"}')"

# 400 = secret OK, code invalid (expected). 401 = secret wrong.
if [[ "$HTTP_STATUS" == "401" ]]; then
  error "Secret mismatch — worker returned 401"
elif [[ "$HTTP_STATUS" == "400" || "$HTTP_STATUS" == "500" ]]; then
  success "Worker is responding correctly (status ${HTTP_STATUS})"
else
  warn "Unexpected status ${HTTP_STATUS} — check worker logs with: wrangler tail"
fi

# ─── 9. Write .env ────────────────────────────────────────────────────────────
ENV_FILE="$SCRIPT_DIR/../.env"

echo ""
ask "9. Write/update the desktop app .env at ${ENV_FILE}? [Y/n]"
read -r WRITE_ENV
if [[ "${WRITE_ENV:-Y}" =~ ^[Yy]$ ]]; then
  update_or_append() {
    local key="$1" value="$2" file="$3"
    if grep -qE "^${key}=" "$file" 2>/dev/null; then
      sed -i.bak "s|^${key}=.*|${key}=${value}|" "$file" && rm -f "${file}.bak"
    else
      echo "${key}=${value}" >> "$file"
    fi
  }

  touch "$ENV_FILE"
  update_or_append "AKIRA_API_URL"   "$WORKER_URL"      "$ENV_FILE"
  update_or_append "GITHUB_APP_SLUG" "$GITHUB_APP_SLUG" "$ENV_FILE"

  # remove old keys if present
  sed -i.bak '/^GITHUB_APP_ID=/d;/^GITHUB_APP_PRIVATE_KEY=/d;/^AKIRA_SECRET=/d' "$ENV_FILE" && rm -f "${ENV_FILE}.bak"

  success ".env updated"
fi

# ─── 10. Callback URL reminder ────────────────────────────────────────────────
echo ""
echo -e "${YELLOW}${BOLD}Important:${RESET} make sure your GitHub App has this callback URL configured:"
echo "  http://localhost:4567"
echo "(GitHub → Settings → Developer settings → GitHub Apps → your app → Callback URL)"
echo ""

# ─── done ─────────────────────────────────────────────────────────────────────
echo -e "${GREEN}${BOLD}Setup complete.${RESET}"
echo ""
echo "Next steps:"
echo "  source .env && cargo tauri build"
echo ""
echo "To rotate the Akira secret later:"
echo "  openssl rand -hex 32 | wrangler secret put AKIRA_SECRET --name akira-github-proxy"
echo "  # then update AKIRA_SECRET in .env and rebuild the app"
echo ""
