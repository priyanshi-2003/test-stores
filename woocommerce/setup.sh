#!/usr/bin/env bash
# WooCommerce test store: http://localhost:8081
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
URL=http://localhost:8081
ADMIN_USER=admin
ADMIN_PASS='Admin12345!'
ADMIN_EMAIL=admin@example.com
CREDS=credentials.env

# Pinned versions (checked together on 2026-11-26).
WP_VERSION=7.1.5            # must match the wordpress image tag in docker-compose.yml
WOO_VERSION=11.3.1          # needs WordPress >= 7.0 and PHP >= 7.4; tested up to WordPress 7.1.5
WP_CLI_VERSION=2.12.0

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
ok()  { printf '\033[1;32m    ✔ %s\033[0m\n' "$*"; }
die() { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }
dc()  { "${DC[@]}" "$@"; }

# wp-cli inside the WordPress container, as the web server user.
wp()  { dc exec -T -u www-data -e HOME=/tmp wordpress wp --path=/var/www/html "$@"; }
# WooCommerce CLI commands (they run as the admin user).
woo() { wp wc "$@" --user="$ADMIN_USER"; }

# Wait until the URL answers (any 2xx/3xx/4xx). 5 s between tries.
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
  die "$url did not answer (last status: ${code:-none}). Check: ${DC[*]} logs wordpress"
}

preflight() {
  command -v curl >/dev/null || die "curl is not installed"
  dc version >/dev/null 2>&1 || die "'${DC[*]}' is not available (install the Docker compose plugin)"
}

install_wp_cli() {
  log "Installing wp-cli $WP_CLI_VERSION in the container"
  dc exec -T wordpress bash -c "
    if ! wp --allow-root --version 2>/dev/null | grep -q '$WP_CLI_VERSION'; then
      curl -fsSL -o /usr/local/bin/wp \
        https://github.com/wp-cli/wp-cli/releases/download/v$WP_CLI_VERSION/wp-cli-$WP_CLI_VERSION.phar
      chmod +x /usr/local/bin/wp
    fi"
  ok "wp-cli $(wp --version)"
}

install_wordpress() {
  local have
  have=$(wp core version)
  [ "$have" = "$WP_VERSION" ] || die "the WordPress files are version $have, expected $WP_VERSION
       (data left over from an older run). Run: ./setup.sh reset   then: ./setup.sh"

  if wp core is-installed >/dev/null 2>&1; then
    ok "WordPress $have already installed"
  else
    log "Installing WordPress $WP_VERSION"
    wp core install --url="$URL" --title="Woo Test Store" \
      --admin_user="$ADMIN_USER" --admin_password="$ADMIN_PASS" \
      --admin_email="$ADMIN_EMAIL" --skip-email
  fi
  # Pretty URLs so /wp-json/... works. The image already ships the matching .htaccess.
  wp rewrite structure '/%postname%/' >/dev/null
  ok "permalinks set"
}

install_woocommerce() {
  log "Installing WooCommerce $WOO_VERSION"
  if ! wp plugin is-installed woocommerce; then
    wp plugin install woocommerce --version="$WOO_VERSION"
  fi
  local have
  have=$(wp plugin get woocommerce --field=version)
  [ "$have" = "$WOO_VERSION" ] || die "WooCommerce $have is installed, expected $WOO_VERSION. Run ./setup.sh reset"
  wp plugin activate woocommerce >/dev/null
  ok "WooCommerce $have active"

  log "Store settings: Romania, RON, cash on delivery, free shipping"
  wp option update woocommerce_coming_soon no >/dev/null
  wp option update woocommerce_store_address "Str. Test 1" >/dev/null
  wp option update woocommerce_store_city "Cluj-Napoca" >/dev/null
  wp option update woocommerce_store_postcode "400000" >/dev/null
  wp option update woocommerce_default_country "RO:CJ" >/dev/null
  wp option update woocommerce_currency "RON" >/dev/null
  woo payment_gateway update cod --enabled=true >/dev/null
  # Zone 0 = "Locations not covered by your other zones", i.e. everywhere.
  if [ -z "$(woo shipping_zone_method list 0 --format=ids)" ]; then
    woo shipping_zone_method create 0 --method_id=free_shipping --enabled=true >/dev/null
  fi
  ok "settings done"
}

create_simple_product() {   # name sku price category_id
  woo product create --type=simple --name="$1" --sku="$2" --regular_price="$3" \
    --categories="[{\"id\":$4}]" --manage_stock=true --stock_quantity=100 \
    --description="Test product: $1." --porcelain >/dev/null
  ok "$2  $1  ($3 RON)"
}

create_products() {
  if [ -n "$(woo product list --format=ids)" ]; then
    ok "products already exist"
    return
  fi
  log "Creating test products"
  local apparel home tshirt size
  apparel=$(woo product_cat create --name="Apparel" --porcelain)
  home=$(woo product_cat create --name="Home and Kitchen" --porcelain)

  create_simple_product "Running Shoes"   WOO-SHOES   349 "$apparel"
  create_simple_product "Leather Wallet"  WOO-WALLET  129 "$apparel"
  create_simple_product "Denim Jacket"    WOO-JACKET  299 "$apparel"
  create_simple_product "Coffee Mug"      WOO-MUG      39 "$home"
  create_simple_product "Desk Lamp"       WOO-LAMP    189 "$home"
  create_simple_product "Cotton Bedsheet" WOO-SHEET   159 "$home"

  # One product with variants (sizes), like most fashion stores.
  tshirt=$(woo product create --type=variable --name="Cotton T-Shirt" --sku=WOO-TSHIRT \
    --categories="[{\"id\":$apparel}]" --description="Test product with sizes." \
    --attributes='[{"name":"Size","options":["S","M","L"],"visible":true,"variation":true}]' \
    --porcelain)
  for size in S M L; do
    woo product_variation create "$tshirt" --sku="WOO-TSHIRT-$size" --regular_price=79 \
      --manage_stock=true --stock_quantity=50 \
      --attributes="[{\"name\":\"Size\",\"option\":\"$size\"}]" --porcelain >/dev/null
  done
  ok "WOO-TSHIRT  Cotton T-Shirt, sizes S/M/L  (79 RON)"
}

create_credentials() {
  if [ -f "$CREDS" ]; then
    ok "credentials already in $CREDS"
    return
  fi
  log "Creating API credentials"
  local app_pass keys ck cs
  app_pass=$(wp user application-password create "$ADMIN_USER" leonardo --porcelain)
  keys=$(wp eval '
    $ck = "ck_" . wc_rand_hash();
    $cs = "cs_" . wc_rand_hash();
    global $wpdb;
    $wpdb->insert($wpdb->prefix . "woocommerce_api_keys", array(
      "user_id" => 1, "description" => "leonardo", "permissions" => "read_write",
      "consumer_key" => wc_api_hash($ck), "consumer_secret" => $cs,
      "truncated_key" => substr($ck, -7)));
    echo $ck . " " . $cs;')
  read -r ck cs <<< "$keys"
  [ -n "$app_pass" ] && [ -n "$ck" ] && [ -n "$cs" ] || die "could not create API credentials"

  cat > "$CREDS" <<EOF
# WooCommerce test store: $URL   admin: $URL/wp-admin   login: $ADMIN_USER / $ADMIN_PASS
WOO_URL=$URL

# Admin REST API (/wp-json/wc/v3/...): basic auth with this application password. Works over plain HTTP.
WOO_APP_USER=$ADMIN_USER
WOO_APP_PASSWORD='$app_pass'

# WooCommerce REST keys: basic auth only over HTTPS; over plain HTTP WooCommerce wants OAuth 1.0a signing.
WOO_CONSUMER_KEY=$ck
WOO_CONSUMER_SECRET=$cs

# Store API (/wp-json/wc/store/v1/...: products, cart, checkout) needs no auth.
EOF
  chmod 600 "$CREDS"
  ok "saved to $CREDS"
}

smoke_test() {
  log "Checking the APIs"
  [ -f "$CREDS" ] || die "$CREDS not found; run ./setup.sh first"
  # shellcheck disable=SC1090
  source "$CREDS"
  curl -sf -m 30 "$URL/wp-json/wc/store/v1/products?search=mug" | grep -q '"sku":"WOO-MUG"' \
    || die "Store API did not return the test products: $URL/wp-json/wc/store/v1/products"
  ok "Store API product search: OK"
  curl -sf -m 30 -u "$WOO_APP_USER:$WOO_APP_PASSWORD" "$URL/wp-json/wc/v3/orders?per_page=1" >/dev/null \
    || die "admin REST API rejected the application password: $URL/wp-json/wc/v3/orders"
  ok "Admin REST API (orders) with application password: OK"
  # Cart writes need the Cart-Token that GET /cart hands out (the same flow an executor will use).
  local token mug
  token=$(curl -sf -m 30 -D - -o /dev/null "$URL/wp-json/wc/store/v1/cart" \
          | tr -d '\r' | awk -F': ' 'tolower($1) == "cart-token" { print $2 }')
  [ -n "$token" ] || die "Store API did not return a Cart-Token header: $URL/wp-json/wc/store/v1/cart"
  mug=$(woo product list --sku=WOO-MUG --format=ids)
  curl -sf -m 30 -X POST "$URL/wp-json/wc/store/v1/cart/add-item" \
       -H "Cart-Token: $token" -H 'Content-Type: application/json' \
       -d "{\"id\": $mug, \"quantity\": 1}" >/dev/null \
    || die "Store API could not add an item to the cart"
  ok "Store API cart (Cart-Token + add-item): OK"
}

install() {
  preflight
  log "Starting containers"
  dc up -d
  wait_http "$URL/wp-login.php"
  install_wp_cli
  install_wordpress
  install_woocommerce
  create_products
  create_credentials
  smoke_test
  printf '\n\033[1;32mWooCommerce is ready.\033[0m\n'
  printf '  Shop:   %s\n  Admin:  %s/wp-admin   (%s / %s)\n  Keys:   ./%s   (./setup.sh creds)\n' \
    "$URL" "$URL" "$ADMIN_USER" "$ADMIN_PASS" "$CREDS"
}

case "${1:-}" in
  "")     install ;;
  status) dc ps ;;
  creds)  cat "$CREDS" ;;
  test)   smoke_test ;;
  logs)   dc logs -f ;;
  stop)   dc stop ;;
  reset)
    read -rp "Delete the WooCommerce containers AND all store data? [y/N] " yn
    [ "$yn" = y ] || exit 0
    dc down -v
    rm -f "$CREDS"
    ok "reset done; run ./setup.sh to install again" ;;
  *) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
