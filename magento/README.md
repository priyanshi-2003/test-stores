# Magento test store

A real Magento Open Source shop in Docker, for testing leonardo executors against its REST API.

| | |
|---|---|
| Shop | http://localhost:8083 |
| Admin | http://localhost:8083/admin, login `admin` / `Admin12345!` |
| Versions | Magento Open Source 2.4.8-p5, PHP 8.3 + Apache, Composer 2.8.12, MariaDB 11.4, OpenSearch 2.19.8 |
| Containers | `magento-magento-1`, `magento-db-1`, `magento-opensearch-1` |
| Data | Docker volumes `magento_db`, `magento_search`, `magento_html` |

These are local test passwords only. Magento's code comes from the free **Mage-OS mirror**, so no Adobe Marketplace keys are needed.

## Run
```bash
chmod +x setup.sh
./setup.sh            # first run 20-30 min; later runs just start it
```
Use `sudo ./setup.sh` if your user isn't in the `docker` group.

On the first run it:
- builds 2 images: PHP with Magento's extensions, and OpenSearch with its plugins;
- starts the 3 containers;
- downloads Magento (~300 MB) and installs it;
- turns off admin 2FA, so API tokens work;
- creates 5 products (`TEST-001` to `TEST-005`);
- saves an admin API token to `credentials.env`;
- tests a guest cart.

| Command | Does |
|---|---|
| `./setup.sh status` | show the containers |
| `./setup.sh creds` | print the API token |
| `./setup.sh token` | print a fresh admin token |
| `./setup.sh test` | re-run the API checks |
| `./setup.sh logs` | follow the logs |
| `./setup.sh stop` | stop (data kept; start again with `./setup.sh`) |
| `./setup.sh reset` | delete containers **and** data (asks first) |

Memory: about 3 GB while running (OpenSearch alone uses 1 GB+). Stop it when you're not testing Magento.

## API calls
Run `source credentials.env` first.

```bash
H="Authorization: Bearer $MAGENTO_ADMIN_TOKEN"

# Products (admin token)
curl -s  -H "$H" "$MAGENTO_URL/rest/V1/products/TEST-001"
curl -sg -H "$H" "$MAGENTO_URL/rest/V1/products?searchCriteria[pageSize]=5"
curl -sg -H "$H" "$MAGENTO_URL/rest/V1/products?searchCriteria[filter_groups][0][filters][0][field]=name&searchCriteria[filter_groups][0][filters][0][value]=%25Shoes%25&searchCriteria[filter_groups][0][filters][0][condition_type]=like"

# Guest checkout: 4 calls, no token
CART=$(curl -s -X POST "$MAGENTO_URL/rest/V1/guest-carts" | tr -d '"')
curl -s -X POST "$MAGENTO_URL/rest/V1/guest-carts/$CART/items" -H 'Content-Type: application/json' \
  -d "{\"cartItem\":{\"sku\":\"TEST-001\",\"qty\":1,\"quote_id\":\"$CART\"}}"
ADDR='{"firstname":"Ana","lastname":"Pop","street":["1 Test St"],"city":"Los Angeles","region_id":12,
       "region_code":"CA","postcode":"90001","country_id":"US","telephone":"5550000000","email":"ana@example.com"}'
curl -s -X POST "$MAGENTO_URL/rest/V1/guest-carts/$CART/shipping-information" -H 'Content-Type: application/json' \
  -d "{\"addressInformation\":{\"shipping_address\":$ADDR,\"billing_address\":$ADDR,
       \"shipping_carrier_code\":\"flatrate\",\"shipping_method_code\":\"flatrate\"}}"
curl -s -X POST "$MAGENTO_URL/rest/V1/guest-carts/$CART/payment-information" -H 'Content-Type: application/json' \
  -d "{\"email\":\"ana@example.com\",\"paymentMethod\":{\"method\":\"checkmo\"},\"billingAddress\":$ADDR}"
# → the new order's id

# Orders (admin token)
curl -sg -H "$H" "$MAGENTO_URL/rest/V1/orders?searchCriteria[pageSize]=5"
curl -s  -H "$H" "$MAGENTO_URL/rest/V1/orders/<order_id>"
curl -sg -H "$H" "$MAGENTO_URL/rest/V1/orders?searchCriteria[filter_groups][0][filters][0][field]=increment_id&searchCriteria[filter_groups][0][filters][0][value]=000000001"
```

Notes for executors:
- **Guest checkout is 4 calls in order:** cart → item → shipping → payment. Each executor is one call, so leonardo has to chain them.
- **Admin tokens** last 1 year here (`oauth/access_token_lifetime/admin = 8760` hours). Real stores often use the 4-hour default; use an Integration token there instead. Integration tokens as bearer are turned on here.

## Problems
| Problem | Fix |
|---|---|
| `permission denied ... docker.sock` | `sudo ./setup.sh`, or `sudo usermod -aG docker $USER` then log out and back in |
| "an earlier download stopped" | `./setup.sh reset`, then `./setup.sh` |
| Download fails (network/DNS) | Check the machine can reach `https://mirror.mage-os.org/`. Docker DNS fix: `{"dns":["8.8.8.8","1.1.1.1"]}` in `/etc/docker/daemon.json`, then `sudo systemctl restart docker` |
| OpenSearch keeps restarting | `./setup.sh logs`. On Linux: `sudo sysctl -w vm.max_map_count=262144` |
| Pages have no styling | `docker compose exec -u www-data magento php bin/magento setup:static-content:deploy -f` |
| Port 8083 in use | Change `"8083:80"` in `docker-compose.yml` and `URL=` in `setup.sh`, then reset |
