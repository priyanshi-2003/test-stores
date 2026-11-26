#!/usr/bin/env bash
# PrestaShop test store: http://localhost:8082
#
#   ./setup.sh          install on the first run, just start on later runs
#   ./setup.sh status   show the containers
#   ./setup.sh creds    print the API credentials
#   ./setup.sh test     re-run the API checks
#   ./setup.sh logs     follow the container logs (Ctrl+C to leave)
#   ./setup.sh stop     stop the store (data kept)
#   ./setup.sh reset    delete the containers AND all store data (asks first)
#
# Safe to re-run: every step checks whether it is already done.
# Podman instead of Docker:  DC="podman compose" ./setup.sh

set -euo pipefail
cd "$(dirname "$0")"

read -ra DC <<< "${DC:-docker compose}"
URL=http://localhost:8082
ADMIN_EMAIL=admin@example.com
ADMIN_PASS='Admin12345!'
CREDS=credentials.env

PS_VERSION=8.2.9   # must match the prestashop image tag in docker-compose.yml

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
ok()  { printf '\033[1;32m    ✔ %s\033[0m\n' "$*"; }
die() { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }
dc()  { "${DC[@]}" "$@"; }
sql() { dc exec -T db mariadb -uroot -proot prestashop -N -e "$1"; }

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
  die "$url did not answer (last status: ${code:-none}). Check: ${DC[*]} logs prestashop"
}

preflight() {
  command -v curl >/dev/null    || die "curl is not installed"
  command -v openssl >/dev/null || die "openssl is not installed"
  dc version >/dev/null 2>&1    || die "'${DC[*]}' is not available (install the Docker compose plugin)"
}

check_install() {
  dc exec -T prestashop test -f /var/www/html/app/config/parameters.php \
    || die "PrestaShop did not install. See: ${DC[*]} logs prestashop"
  local have
  have=$(dc exec -T prestashop grep -oE "const VERSION = '[0-9.]+'" /var/www/html/src/Core/Version.php \
         | grep -oE "[0-9]+(\.[0-9]+)+" || true)
  [ "$have" = "$PS_VERSION" ] || die "PrestaShop files are $have, expected $PS_VERSION. Run ./setup.sh reset"
  ok "PrestaShop $have installed (demo products and orders included)"
}

enable_webservice() {
  if [ -f "$CREDS" ]; then
    ok "webservice key already in $CREDS"
    return
  fi
  log "Turning on the webservice API and creating a key"
  local key resources perms="" r m
  key=$(openssl rand -hex 16 | tr 'a-f' 'A-F')   # 32 characters, A-Z0-9, as PrestaShop expects
  resources="addresses carriers cart_rules carts categories combinations configurations contacts
    countries currencies customer_messages customer_threads customers customizations deliveries
    groups guests image_types images languages manufacturers messages order_carriers order_details
    order_histories order_invoices order_payments order_slip order_states orders price_ranges
    product_customization_fields product_feature_values product_features product_option_values
    product_options products search shop_groups shop_urls shops specific_prices states
    stock_availables stock_movements stores suppliers tags tax_rule_groups tax_rules taxes
    translated_configurations weight_ranges zones"
  for r in $resources; do
    for m in GET POST PUT PATCH DELETE HEAD; do perms+="('$r','$m',@id),"; done
  done
  sql "
    UPDATE ps_configuration SET value = '1', date_upd = NOW() WHERE name = 'PS_WEBSERVICE';
    INSERT INTO ps_configuration (name, value, date_add, date_upd)
      SELECT 'PS_WEBSERVICE', '1', NOW(), NOW() FROM DUAL
      WHERE NOT EXISTS (SELECT 1 FROM ps_configuration WHERE name = 'PS_WEBSERVICE');
    INSERT INTO ps_webservice_account (\`key\`, description, class_name, is_module, module_name, active)
      VALUES ('$key', 'leonardo', 'WebserviceRequest', 0, NULL, 1);
    SET @id = LAST_INSERT_ID();
    INSERT INTO ps_webservice_account_shop (id_webservice_account, id_shop) VALUES (@id, 1);
    INSERT INTO ps_webservice_permission (resource, method, id_webservice_account) VALUES ${perms%,};"

  # Rewrite .htaccess so /api/... is routed to the webservice (same as saving Traffic & SEO in admin).
  dc exec -T -u www-data prestashop php -r \
    'require "/var/www/html/config/config.inc.php"; Tools::generateHtaccess();' >/dev/null 2>&1 || true

  cat > "$CREDS" <<EOF
# PrestaShop test store: $URL   admin: $URL/admin-dev   login: $ADMIN_EMAIL / $ADMIN_PASS
PRESTA_URL=$URL

# Webservice key: send as ?ws_key=... or as the basic-auth username with an empty password.
# Always add output_format=JSON (the default is XML). Writes (POST/PUT) take XML bodies.
PRESTA_WS_KEY=$key
EOF
  chmod 600 "$CREDS"
  ok "key saved to $CREDS"
}

smoke_test() {
  log "Checking the API"
  [ -f "$CREDS" ] || die "$CREDS not found; run ./setup.sh first"
  # shellcheck disable=SC1090
  source "$CREDS"
  local q="ws_key=$PRESTA_WS_KEY&output_format=JSON"
  if curl -sfg -m 30 "$URL/api/products?$q&limit=1" | grep -q '"products"'; then
    ok "GET /api/products: OK"
  elif curl -sfg -m 30 "$URL/webservice/dispatcher.php?url=products&$q&limit=1" | grep -q '"products"'; then
    ok "GET /webservice/dispatcher.php?url=products: OK"
    ok "(the short /api/ address is off; to turn it on: admin > Shop Parameters > Traffic & SEO > Save)"
  else
    die "the webservice did not answer. Check: ${DC[*]} logs prestashop"
  fi
  curl -sfg -m 30 "$URL/webservice/dispatcher.php?url=orders&$q&limit=1" | grep -q '"orders"' \
    || die "GET orders failed"
  ok "GET orders: OK"
}

install() {
  preflight
  log "Starting containers (the first start installs PrestaShop: 3-6 min)"
  dc up -d
  wait_http "$URL/" 180
  check_install
  enable_webservice
  smoke_test
  printf '\n\033[1;32mPrestaShop is ready.\033[0m\n'
  printf '  Shop:   %s\n  Admin:  %s/admin-dev   (%s / %s)\n  Key:    ./%s   (./setup.sh creds)\n' \
    "$URL" "$URL" "$ADMIN_EMAIL" "$ADMIN_PASS" "$CREDS"
}

case "${1:-}" in
  "")     install ;;
  status) dc ps ;;
  creds)  cat "$CREDS" ;;
  test)   smoke_test ;;
  logs)   dc logs -f ;;
  stop)   dc stop ;;
  reset)
    read -rp "Delete the PrestaShop containers AND all store data? [y/N] " yn
    [ "$yn" = y ] || exit 0
    dc down -v
    rm -f "$CREDS"
    ok "reset done; run ./setup.sh to install again" ;;
  *) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
