#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

info()    { echo -e "${CYAN}${BOLD}→${RESET} $*"; }
success() { echo -e "${GREEN}${BOLD}✓${RESET} $*"; }
warn()    { echo -e "${YELLOW}${BOLD}!${RESET} $*"; }
error()   { echo -e "${RED}${BOLD}✗${RESET} $*" >&2; exit 1; }
ask()     { echo -e "${BOLD}$*${RESET}"; }

command -v wrangler >/dev/null 2>&1 || error "wrangler not found — run: npm install -g wrangler"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo ""
echo -e "${BOLD}Akira GitHub Proxy — Full Setup${RESET}"
echo "─────────────────────────────────────"
echo ""

# ─── 1. GitHub OAuth ──────────────────────────────────────────────────────────
echo -e "${BOLD}GitHub OAuth${RESET}"
echo "(GitHub → Settings → Developer settings → GitHub Apps → your app)"
echo ""

ask "GitHub App slug (the name in the install URL, e.g. 'my-akira-app'):"
read -r GITHUB_APP_SLUG
[[ -n "$GITHUB_APP_SLUG" ]] || error "App slug cannot be empty"

ask "GitHub OAuth Client ID (starts with Iv1.):"
read -r GITHUB_CLIENT_ID
[[ -n "$GITHUB_CLIENT_ID" ]] || error "Client ID cannot be empty"

ask "GitHub OAuth Client Secret:"
read -rs GITHUB_CLIENT_SECRET
echo ""
[[ -n "$GITHUB_CLIENT_SECRET" ]] || error "Client Secret cannot be empty"

# ─── 2. GitHub App (for installation tokens) ─────────────────────────────────
echo ""
echo -e "${BOLD}GitHub App${RESET}"
echo "(GitHub → Settings → Developer settings → GitHub Apps → your app → General)"
echo ""

ask "GitHub App ID (numeric, shown on the app page):"
read -r GITHUB_APP_ID
[[ -n "$GITHUB_APP_ID" ]] || error "App ID cannot be empty"

ask "GitHub App Private Key — enter path to .pem file (or press Enter to paste):"
read -r PEM_PATH
if [[ -n "$PEM_PATH" ]]; then
  [[ -f "$PEM_PATH" ]] || error "File not found: $PEM_PATH"
  GITHUB_PRIVATE_KEY="$(cat "$PEM_PATH")"
else
  ask "Paste the private key (PEM format, end with a blank line):"
  GITHUB_PRIVATE_KEY=""
  while IFS= read -r line; do
    [[ -z "$line" ]] && break
    GITHUB_PRIVATE_KEY="${GITHUB_PRIVATE_KEY}${line}\n"
  done
fi
[[ -n "$GITHUB_PRIVATE_KEY" ]] || error "Private key cannot be empty"

# ─── 3. Stripe ────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}Stripe${RESET}"
echo "(Stripe Dashboard → Developers → API keys)"
echo ""

ask "Stripe Secret Key (starts with sk_):"
read -rs STRIPE_SECRET_KEY
echo ""
[[ -n "$STRIPE_SECRET_KEY" ]] || error "Stripe Secret Key cannot be empty"

ask "Stripe Webhook Secret (starts with whsec_ — from Stripe Dashboard → Webhooks):"
read -rs STRIPE_WEBHOOK_SECRET
echo ""
[[ -n "$STRIPE_WEBHOOK_SECRET" ]] || error "Stripe Webhook Secret cannot be empty"

# ─── 4. Usage HMAC ───────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}Usage HMAC Secret${RESET}"
echo ""

ask "USAGE_HMAC_SECRET — press Enter to generate automatically, or paste an existing one:"
read -rs USAGE_HMAC_INPUT
echo ""
if [[ -z "$USAGE_HMAC_INPUT" ]]; then
  USAGE_HMAC_SECRET="$(openssl rand -hex 32)"
  success "Generated USAGE_HMAC_SECRET: ${BOLD}${USAGE_HMAC_SECRET}${RESET}"
  warn "Save this value — you'll need it if you redeploy."
else
  USAGE_HMAC_SECRET="$USAGE_HMAC_INPUT"
fi

# ─── 5. Mailgun ──────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}Mailgun${RESET}"
echo "(Mailgun Dashboard → Sending → Domains → your domain → API Keys)"
echo ""

ask "Mailgun API Key:"
read -rs MAILGUN_API_KEY
echo ""
[[ -n "$MAILGUN_API_KEY" ]] || error "Mailgun API Key cannot be empty"

ask "Mailgun sending domain [akira-io.com]:"
read -r MAILGUN_DOMAIN_INPUT
MAILGUN_DOMAIN="${MAILGUN_DOMAIN_INPUT:-akira-io.com}"
success "Using Mailgun domain: ${BOLD}${MAILGUN_DOMAIN}${RESET}"

# ─── 6. Install dependencies ─────────────────────────────────────────────────
echo ""
info "Installing worker dependencies..."
npm install --silent
success "Dependencies installed"

# ─── 7. Push secrets to Cloudflare ───────────────────────────────────────────
echo ""
info "Pushing secrets to Cloudflare Workers..."

printf '%s' "$GITHUB_CLIENT_ID"     | wrangler secret put GITHUB_CLIENT_ID     --name akira-github-proxy
printf '%s' "$GITHUB_CLIENT_SECRET" | wrangler secret put GITHUB_CLIENT_SECRET --name akira-github-proxy
printf '%s' "$GITHUB_APP_ID"        | wrangler secret put GITHUB_APP_ID        --name akira-github-proxy
printf '%s' "$GITHUB_PRIVATE_KEY"   | wrangler secret put GITHUB_PRIVATE_KEY   --name akira-github-proxy
printf '%s' "$STRIPE_SECRET_KEY"    | wrangler secret put STRIPE_SECRET_KEY    --name akira-github-proxy
printf '%s' "$STRIPE_WEBHOOK_SECRET"| wrangler secret put STRIPE_WEBHOOK_SECRET --name akira-github-proxy
printf '%s' "$USAGE_HMAC_SECRET"    | wrangler secret put USAGE_HMAC_SECRET    --name akira-github-proxy
printf '%s' "$MAILGUN_API_KEY"      | wrangler secret put MAILGUN_API_KEY      --name akira-github-proxy
printf '%s' "$MAILGUN_DOMAIN"       | wrangler secret put MAILGUN_DOMAIN       --name akira-github-proxy

success "All secrets stored"

# ─── 8. Deploy ────────────────────────────────────────────────────────────────
echo ""
info "Deploying worker..."
DEPLOY_OUTPUT="$(wrangler deploy 2>&1)"
echo "$DEPLOY_OUTPUT"

WORKER_URL="$(echo "$DEPLOY_OUTPUT" | grep -oE 'https://[a-z0-9._-]+\.workers\.dev' | head -1)"
[[ -n "$WORKER_URL" ]] || error "Could not extract worker URL from deploy output"

success "Worker deployed at: ${BOLD}${WORKER_URL}${RESET}"

# ─── 9. Write .env ────────────────────────────────────────────────────────────
ENV_FILE="$SCRIPT_DIR/../.env"

echo ""
ask "Write/update the desktop app .env at ${ENV_FILE}? [Y/n]"
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

  sed -i.bak '/^GITHUB_APP_ID=/d;/^GITHUB_APP_PRIVATE_KEY=/d;/^AKIRA_SECRET=/d' "$ENV_FILE" && rm -f "${ENV_FILE}.bak"

  success ".env updated"
fi

# ─── 10. Stripe webhook reminder ─────────────────────────────────────────────
echo ""
echo -e "${YELLOW}${BOLD}Stripe webhook:${RESET} make sure your webhook endpoint is configured at:"
echo "  ${WORKER_URL}/billing/webhook"
echo "With these events:"
echo "  customer.subscription.deleted"
echo "  customer.subscription.updated"
echo "  invoice.payment_failed"
echo "  invoice.payment_succeeded"
echo ""

# ─── 11. GitHub callback reminder ────────────────────────────────────────────
echo -e "${YELLOW}${BOLD}GitHub App:${RESET} make sure the callback URL is:"
echo "  http://localhost:4567"
echo ""

# ─── done ─────────────────────────────────────────────────────────────────────
echo -e "${GREEN}${BOLD}Setup complete.${RESET}"
echo ""
echo "Next steps:"
echo "  source .env && cargo tauri build"
echo ""
echo "To rotate any secret later:"
echo "  printf '%s' 'new-value' | wrangler secret put SECRET_NAME --name akira-github-proxy"
echo ""
