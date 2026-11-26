# WooCommerce test store

A real WooCommerce shop in Docker, for testing leonardo executors against its APIs.

| | |
|---|---|
| Shop | http://localhost:8081 |
| Admin | http://localhost:8081/wp-admin, login `admin` / `Admin12345!` |
| Versions | WordPress 7.1.5 (PHP 8.3, Apache), WooCommerce 11.3.1, MariaDB 11.4, wp-cli 2.12.0 |
| Containers | `woocommerce-wordpress-1`, `woocommerce-db-1` |
| Data | Docker volumes `woocommerce_db`, `woocommerce_html` |

These are local test passwords only.

## Run
```bash
chmod +x setup.sh
./setup.sh            # first run ~3-5 min; later runs just start it
```
Use `sudo ./setup.sh` if your user isn't in the `docker` group.

On the first run it:
- starts the 2 containers;
- installs WordPress and WooCommerce;
- sets Romania / RON, cash on delivery and free shipping;
- creates 7 test products (one with sizes S/M/L);
- creates API credentials in `credentials.env`;
- checks the APIs answer.

| Command | Does |
|---|---|
| `./setup.sh status` | show the containers |
| `./setup.sh creds` | print the API credentials |
| `./setup.sh test` | re-run the API checks |
| `./setup.sh logs` | follow the logs |
| `./setup.sh stop` | stop (data kept; start again with `./setup.sh`) |
| `./setup.sh reset` | delete containers **and** data (asks first) |

## Test products
| SKU | Name | Price (RON) |
|---|---|---|
| WOO-SHOES | Running Shoes | 349 |
| WOO-WALLET | Leather Wallet | 129 |
| WOO-JACKET | Denim Jacket | 299 |
| WOO-MUG | Coffee Mug | 39 |
| WOO-LAMP | Desk Lamp | 189 |
| WOO-SHEET | Cotton Bedsheet | 159 |
| WOO-TSHIRT-S / -M / -L | Cotton T-Shirt (variable) | 79 |

## API calls (the ones the executors will use)
Run `source credentials.env` first.

```bash
# 1. Search products (Store API, no auth)
curl -s "$WOO_URL/wp-json/wc/store/v1/products?search=shoes"

# 2. Get a cart token (from the response header)
TOKEN=$(curl -s -D - -o /dev/null "$WOO_URL/wp-json/wc/store/v1/cart" | tr -d '\r' | awk -F': ' 'tolower($1)=="cart-token"{print $2}')

# 3. Add to cart (product id from step 1; for the T-shirt use a variation id)
curl -s -X POST "$WOO_URL/wp-json/wc/store/v1/cart/add-item" \
  -H "Cart-Token: $TOKEN" -H 'Content-Type: application/json' -d '{"id": <product_id>, "quantity": 1}'

# 4. Place the order (cash on delivery)
curl -s -X POST "$WOO_URL/wp-json/wc/store/v1/checkout" \
  -H "Cart-Token: $TOKEN" -H 'Content-Type: application/json' -d '{
    "billing_address": {"first_name":"Ana","last_name":"Pop","address_1":"Str. Test 1","city":"Cluj-Napoca",
                        "state":"CJ","postcode":"400000","country":"RO","email":"ana@example.com","phone":"0700000000"},
    "shipping_address": {"first_name":"Ana","last_name":"Pop","address_1":"Str. Test 1","city":"Cluj-Napoca",
                        "state":"CJ","postcode":"400000","country":"RO"},
    "payment_method": "cod"}'
# → {"order_id": ..., "status": "processing", ...}

# 5. Look up orders (admin REST API, application password)
curl -s -u "$WOO_APP_USER:$WOO_APP_PASSWORD" "$WOO_URL/wp-json/wc/v3/orders?per_page=5"
curl -s -u "$WOO_APP_USER:$WOO_APP_PASSWORD" "$WOO_URL/wp-json/wc/v3/orders/<order_id>"
curl -s -u "$WOO_APP_USER:$WOO_APP_PASSWORD" "$WOO_URL/wp-json/wc/v3/orders?search=ana@example.com"
```

Notes:
- **Store API** (`/wc/store/v1`): products, cart, checkout. No login. Cart writes need the `Cart-Token` from step 2.
- **Admin REST API** (`/wc/v3`): orders, products, customers. Uses the application password over HTTP. The `ck_/cs_` keys in `credentials.env` work as basic auth only over HTTPS.

## Problems
| Problem | Fix |
|---|---|
| `permission denied ... docker.sock` | `sudo ./setup.sh`, or `sudo usermod -aG docker $USER` then log out and back in |
| "WordPress files are version X, expected 7.1.5" | Data left from an older run: `./setup.sh reset`, then `./setup.sh` |
| Downloads fail inside the container (DNS) | Add `{"dns":["8.8.8.8","1.1.1.1"]}` to `/etc/docker/daemon.json` (check it's empty first), then `sudo systemctl restart docker` |
| Port 8081 in use | Change `"8081:80"` in `docker-compose.yml` and `URL=` in `setup.sh`, then `./setup.sh reset` and `./setup.sh` |
