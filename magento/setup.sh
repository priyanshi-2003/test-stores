#!/usr/bin/env bash
# Magento Open Source test store: http://localhost:8083
#
#   ./setup.sh          install on the first run (20-30 min), just start on later runs
#   ./setup.sh status   show the containers
#   ./setup.sh creds    print the API credentials
#   ./setup.sh test     re-run the API checks
#   ./setup.sh token    print a fresh admin API token
#   ./setup.sh logs     follow the container logs (Ctrl+C to leave)
#   ./setup.sh stop     stop the store (data kept)
#   ./setup.sh reset    delete the containers AND all store data (asks first)
#
# Safe to re-run: every step checks whether it is already done.
# Podman instead of Docker:  DC="podman compose" ./setup.sh

set -euo pipefail
cd "$(dirname "$0")"

read -ra DC <<< "${DC:-docker compose}"
URL=http://localhost:8083
ADMIN_USER=admin
ADMIN_PASS='Admin12345!'
ADMIN_EMAIL=admin@example.com
CREDS=credentials.env

MAGENTO_VERSION=2.4.8-p5   # Magento Open Source, from the Mage-OS mirror (no Adobe keys needed)
MIRROR=https://mirror.mage-os.org/
DONE_MARKER=var/.store-setup-done

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
ok()  { printf '\033[1;32m    ✔ %s\033[0m\n' "$*"; }
die() { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }
dc()  { "${DC[@]}" "$@"; }
# Run a shell command in the Magento container, in /var/www/html, as the web server user.
mx()  { dc exec -T -u www-data -w /var/www/html magento bash -c "$1"; }

wait_http() {
  local url=$1 tries=${2:-60} code=""
  printf '    waiting for %s ' "$url"
  for ((i = 1; i <= tries; i++)); do
    code=$(curl -s -m 10 -o /dev/null -w '%{http_code}' "$url" || true)
    case $code in 2??|3??|4??) printf '\n'; return 0 ;; esac
    printf '.'
    sleep 5
  done
  printf '\n'
  die "$url did not answer (last status: ${code:-none}). Check: ${DC[*]} logs magento"
}

preflight() {
  command -v curl >/dev/null || die "curl is not installed"
  dc version >/dev/null 2>&1 || die "'${DC[*]}' is not available (install the Docker compose plugin)"
}

admin_token() {
  curl -sf -m 30 -X POST "$URL/rest/V1/integration/admin/token" -H 'Content-Type: application/json' \
       -d "{\"username\":\"$ADMIN_USER\",\"password\":\"$ADMIN_PASS\"}" | tr -d '"' \
    || die "could not get an admin token from $URL/rest/V1/integration/admin/token"
}

download_magento() {
  if mx 'test -f bin/magento'; then
    ok "Magento code already downloaded"
  else
    mx 'test -z "$(ls -A)"' || die "/var/www/html has files but no Magento (an earlier download stopped).
       Run: ./setup.sh reset   then: ./setup.sh"
    log "Downloading Magento $MAGENTO_VERSION from the Mage-OS mirror (5-15 min)"
    mx "composer create-project --no-interaction --no-progress --repository-url=$MIRROR \
          magento/project-community-edition=$MAGENTO_VERSION ."
  fi
  local have
  have=$(mx 'php bin/magento --version' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+(-p[0-9]+)?' || true)
  [ "$have" = "$MAGENTO_VERSION" ] || die "Magento code is '$have', expected $MAGENTO_VERSION. Run ./setup.sh reset"
  ok "Magento $have"
}

install_magento() {
  if mx "test -f $DONE_MARKER"; then
    ok "Magento already installed"
    return
  fi
  log "Installing Magento (5-10 min)"
  mx "php bin/magento setup:install \
        --base-url=$URL/ --use-rewrites=1 --backend-frontname=admin \
        --db-host=db --db-name=magento --db-user=root --db-password=root --cleanup-database \
        --admin-firstname=Admin --admin-lastname=User --admin-email=$ADMIN_EMAIL \
        --admin-user=$ADMIN_USER --admin-password='$ADMIN_PASS' \
        --language=en_US --currency=USD --timezone=Europe/Bucharest \
        --search-engine=opensearch --opensearch-host=opensearch --opensearch-port=9200"

  log "Turning off admin 2FA (so API tokens work) and making admin tokens last a year"
  mx 'php bin/magento module:disable Magento_AdminAdobeImsTwoFactorAuth Magento_TwoFactorAuth \
      && php bin/magento setup:upgrade \
      && php bin/magento config:set oauth/access_token_lifetime/admin 8760 \
      && php bin/magento config:set oauth/consumer/enable_integration_as_bearer 1 \
      && php bin/magento cache:flush'
  mx "touch $DONE_MARKER"
  ok "installed"
}

create_products() {
  local token=$1 count
  count=$(curl -sfg -m 30 -H "Authorization: Bearer $token" \
            "$URL/rest/V1/products?searchCriteria[pageSize]=1" \
          | grep -oE '"total_count":[0-9]+' | cut -d: -f2 || true)
  if [ "${count:-0}" -gt 0 ]; then
    ok "products already exist ($count)"
    return
  fi
  log "Creating test products"
  local i=0 name price
  while IFS='|' read -r name price; do
    i=$((i + 1))
    curl -sf -m 30 -X POST "$URL/rest/V1/products" \
      -H "Authorization: Bearer $token" -H 'Content-Type: application/json' \
      -d "{\"product\":{\"sku\":\"TEST-00$i\",\"name\":\"$name\",\"attribute_set_id\":4,
           \"price\":$price,\"status\":1,\"visibility\":4,\"type_id\":\"simple\",\"weight\":1,
           \"extension_attributes\":{\"website_ids\":[1],
             \"category_links\":[{\"position\":0,\"category_id\":\"2\"}],
             \"stock_item\":{\"qty\":100,\"is_in_stock\":true}}}}" >/dev/null \
      || die "could not create product TEST-00$i"
    ok "TEST-00$i  $name  (\$$price)"
  done <<'EOF'
Cotton T-Shirt|25
Running Shoes|89
Leather Wallet|39
Coffee Mug|12
Desk Lamp|45
EOF
  log "Reindexing"
  mx 'php bin/magento indexer:reindex && php bin/magento cache:flush' >/dev/null
  ok "done"
}

write_credentials() {
  local token=$1
  cat > "$CREDS" <<EOF
# Magento test store: $URL   admin: $URL/admin   login: $ADMIN_USER / $ADMIN_PASS
MAGENTO_URL=$URL

# Admin API token (valid 1 year). For a fresh one: ./setup.sh token
MAGENTO_ADMIN_TOKEN=$token

# Guest cart / checkout (/rest/V1/guest-carts/...) needs no token.
EOF
  chmod 600 "$CREDS"
  ok "saved to $CREDS"
}

smoke_test() {
  log "Checking the APIs"
  [ -f "$CREDS" ] || die "$CREDS not found; run ./setup.sh first"
  # shellcheck disable=SC1090
  source "$CREDS"
  curl -sf -m 30 -H "Authorization: Bearer $MAGENTO_ADMIN_TOKEN" "$URL/rest/V1/products/TEST-001" \
    | grep -q '"sku":"TEST-001"' || die "GET /rest/V1/products/TEST-001 failed"
  ok "Admin API (product by SKU): OK"
  local cart
  cart=$(curl -sf -m 30 -X POST "$URL/rest/V1/guest-carts" | tr -d '"') || die "could not create a guest cart"
  curl -sf -m 30 -X POST "$URL/rest/V1/guest-carts/$cart/items" -H 'Content-Type: application/json' \
       -d "{\"cartItem\":{\"sku\":\"TEST-004\",\"qty\":1,\"quote_id\":\"$cart\"}}" >/dev/null \
    || die "could not add TEST-004 to a guest cart"
  ok "Guest cart (create + add item): OK"
}

install() {
  preflight
  log "Building images (first time ~5 min) and starting containers"
  dc up -d --build
  download_magento
  install_magento
  wait_http "$URL/" 60
  local token
  token=$(admin_token)
  create_products "$token"
  write_credentials "$token"
  smoke_test
  printf '\n\033[1;32mMagento is ready.\033[0m\n'
  printf '  Shop:   %s\n  Admin:  %s/admin   (%s / %s)\n  Keys:   ./%s   (./setup.sh creds)\n' \
    "$URL" "$URL" "$ADMIN_USER" "$ADMIN_PASS" "$CREDS"
}

case "${1:-}" in
  "")     install ;;
  status) dc ps ;;
  creds)  cat "$CREDS" ;;
  test)   smoke_test ;;
  token)  admin_token; echo ;;
  logs)   dc logs -f ;;
  stop)   dc stop ;;
  reset)
    read -rp "Delete the Magento containers AND all store data? [y/N] " yn
    [ "$yn" = y ] || exit 0
    dc down -v
    rm -f "$CREDS"
    ok "reset done; run ./setup.sh to install again" ;;
  *) sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
