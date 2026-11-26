#!/usr/bin/env bash
# OpenCart test store: http://localhost:8084
#
#   ./setup.sh          install on the first run, just start on later runs
#   ./setup.sh status   show the containers
#   ./setup.sh creds    print the API credentials
#   ./setup.sh test     re-run the API check (a signed call)
#   ./setup.sh allow-ip <ip>   let another machine call the API
#   ./setup.sh logs     follow the container logs (Ctrl+C to leave)
#   ./setup.sh stop     stop the store (data kept)
#   ./setup.sh reset    delete the containers AND all store data (asks first)
#
# Safe to re-run: every step checks whether it is already done.
# Podman instead of Docker:  DC="podman compose" ./setup.sh

set -euo pipefail
cd "$(dirname "$0")"

read -ra DC <<< "${DC:-docker compose}"
URL=http://localhost:8084
ADMIN_USER=admin
ADMIN_PASS='Admin12345!'
ADMIN_EMAIL=admin@example.com
CREDS=credentials.env

OC_VERSION=4.1.0.4   # must match OC_VERSION in the Dockerfile

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
ok()  { printf '\033[1;32m    ✔ %s\033[0m\n' "$*"; }
die() { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }
dc()  { "${DC[@]}" "$@"; }
sql() { dc exec -T db mariadb -uroot -proot opencart -N -e "$1"; }

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
  die "$url did not answer (last status: ${code:-none}). Check: ${DC[*]} logs opencart"
}

preflight() {
  command -v curl >/dev/null    || die "curl is not installed"
  command -v openssl >/dev/null || die "openssl is not installed (needed to sign API calls)"
  dc version >/dev/null 2>&1    || die "'${DC[*]}' is not available (install the Docker compose plugin)"
}

install_opencart() {
  local have
  have=$(dc exec -T opencart grep -oE "define\('VERSION', '[0-9.]+'\)" /var/www/html/index.php \
         | grep -oE "[0-9]+(\.[0-9]+)+" || true)
  [ "$have" = "$OC_VERSION" ] || die "OpenCart files are '$have', expected $OC_VERSION. Run ./setup.sh reset"

  if ! dc exec -T opencart test -d /var/www/html/install; then
    ok "OpenCart $have already installed"
    return
  fi
  log "Installing OpenCart $have (with demo products)"
  dc exec -T -u www-data -w /var/www/html/install opencart php cli_install.php install \
    --username "$ADMIN_USER" --password "$ADMIN_PASS" --email "$ADMIN_EMAIL" \
    --http_server "$URL/" --language en-gb \
    --db_driver mysqli --db_hostname db --db_username root --db_password root \
    --db_database opencart --db_port 3306 --db_prefix oc_
  dc exec -T opencart grep -q "define('DB_DATABASE', 'opencart')" /var/www/html/config.php \
    || die "OpenCart install did not finish (config.php not written). See the output above."
  dc exec -T opencart rm -rf /var/www/html/install
  ok "installed"
}

allow_ip() {   # allow_ip <ip>
  local api_id
  api_id=$(sql "SELECT api_id FROM oc_api WHERE username = 'Default' LIMIT 1")
  [ -n "$api_id" ] || die "OpenCart has no 'Default' API user"
  sql "INSERT INTO oc_api_ip (api_id, ip) SELECT $api_id, '$1' FROM DUAL
       WHERE NOT EXISTS (SELECT 1 FROM oc_api_ip WHERE api_id = $api_id AND ip = '$1')"
  ok "API allowed from $1"
}

setup_api() {
  log "Allowing this machine to call the API"
  # OpenCart checks the caller's IP. Calls from this machine reach the container from the
  # Docker network gateway, so read that address from the web server's access log.
  curl -s -m 10 -o /dev/null "$URL/"
  local ip
  ip=$(dc logs --no-log-prefix --tail 30 opencart 2>/dev/null \
       | grep -oE '^[0-9]+(\.[0-9]+){3}' | tail -1 || true)
  allow_ip 127.0.0.1
  [ -n "$ip" ] && allow_ip "$ip"

  local key
  key=$(sql "SELECT \`key\` FROM oc_api WHERE username = 'Default' LIMIT 1")
  cat > "$CREDS" <<EOF
# OpenCart test store: $URL   admin: $URL/admin   login: $ADMIN_USER / $ADMIN_PASS
OPENCART_URL=$URL

# API user. Every API call must be HMAC-SHA1 signed with this key and come from an allowed IP.
# Use ./oc-api.sh to make signed calls. Allowed IPs: 127.0.0.1 ${ip:-}
OPENCART_API_USERNAME=Default
OPENCART_API_KEY=$key
EOF
  chmod 600 "$CREDS"
  ok "saved to $CREDS"
}

smoke_test() {
  log "Checking the API (a signed call)"
  [ -f "$CREDS" ] || die "$CREDS not found; run ./setup.sh first"
  curl -sf -m 30 "$URL/" >/dev/null || die "the shop page did not load: $URL/"
  ok "Shop page: OK"
  ./oc-api.sh cart >/dev/null || die "the signed API call was refused. Check the allowed IP (./setup.sh allow-ip <ip>)"
  ok "Signed API call (api/order, call=cart): OK"
}

install() {
  preflight
  log "Building the image (first time ~3 min) and starting containers"
  dc up -d --build
  wait_http "$URL/" 60
  install_opencart
  setup_api
  smoke_test
  printf '\n\033[1;32mOpenCart is ready.\033[0m\n'
  printf '  Shop:   %s\n  Admin:  %s/admin   (%s / %s)\n  Keys:   ./%s   (./setup.sh creds)\n' \
    "$URL" "$URL" "$ADMIN_USER" "$ADMIN_PASS" "$CREDS"
}

case "${1:-}" in
  "")       install ;;
  status)   dc ps ;;
  creds)    cat "$CREDS" ;;
  test)     smoke_test ;;
  allow-ip) allow_ip "${2:?usage: ./setup.sh allow-ip <ip>}" ;;
  logs)     dc logs -f ;;
  stop)     dc stop ;;
  reset)
    read -rp "Delete the OpenCart containers AND all store data? [y/N] " yn
    [ "$yn" = y ] || exit 0
    dc down -v
    rm -f "$CREDS"
    ok "reset done; run ./setup.sh to install again" ;;
  *) sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
