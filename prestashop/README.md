# PrestaShop test store

A real PrestaShop shop in Docker, for testing leonardo executors against its webservice API.

| | |
|---|---|
| Shop | http://localhost:8082 |
| Admin | http://localhost:8082/admin-dev, login `admin@example.com` / `Admin12345!` |
| Versions | PrestaShop 8.2.9 (PHP 8.1, Apache), MariaDB 10.11 |
| Containers | `prestashop-prestashop-1`, `prestashop-db-1` |
| Data | Docker volumes `prestashop_db`, `prestashop_html` |

These are local test passwords only.

## Run
```bash
chmod +x setup.sh
./setup.sh            # first run ~5 min; later runs just start it
```
Use `sudo ./setup.sh` if your user isn't in the `docker` group.

On the first run it:
- starts the 2 containers;
- PrestaShop installs itself, with demo products, customers and orders;
- turns on the webservice API and creates a key with read/write access, saved to `credentials.env`;
- checks the API answers.

| Command | Does |
|---|---|
| `./setup.sh status` | show the containers |
| `./setup.sh creds` | print the API key |
| `./setup.sh test` | re-run the API checks |
| `./setup.sh logs` | follow the logs |
| `./setup.sh stop` | stop (data kept; start again with `./setup.sh`) |
| `./setup.sh reset` | delete containers **and** data (asks first) |

## API calls
Run `source credentials.env` first.

```bash
K="ws_key=$PRESTA_WS_KEY&output_format=JSON"

# Products
curl -sg "$PRESTA_URL/api/products?$K&display=[id,name,price,reference]&limit=5"
curl -sg "$PRESTA_URL/api/products/1?$K"
curl -sg "$PRESTA_URL/api/products?$K&display=full&filter[name]=%[shirt]%"     # search by name

# Orders
curl -sg "$PRESTA_URL/api/orders?$K&display=[id,reference,current_state,total_paid]&limit=5"
curl -sg "$PRESTA_URL/api/orders/1?$K"
curl -sg "$PRESTA_URL/api/orders?$K&display=full&filter[reference]=[XKBKNABJK]"  # by order reference

# Creating a cart / order: XML bodies. Get an empty template first:
curl -sg "$PRESTA_URL/api/carts?ws_key=$PRESTA_WS_KEY&schema=blank"
```
If `/api/...` returns 404, use `/webservice/dispatcher.php?url=products&...` instead.

Notes for executors:
- Auth: `ws_key` query parameter, or basic auth with the key as the username and an empty password.
- **Reads** return JSON with `output_format=JSON`. **Writes** (`POST/PUT` carts, orders, addresses) need **XML** bodies.
- Placing an order takes several calls: customer → address → cart → order (with carrier and payment module).

## Problems
| Problem | Fix |
|---|---|
| `permission denied ... docker.sock` | `sudo ./setup.sh`, or `sudo usermod -aG docker $USER` then log out and back in |
| "PrestaShop did not install" | `./setup.sh logs` shows the installer's error. Then `./setup.sh reset` and `./setup.sh` |
| First start looks stuck | Normal for 3–6 min while PrestaShop installs. Watch with `./setup.sh logs` |
| Port 8082 in use | Change `"8082:80"` and `PS_DOMAIN` in `docker-compose.yml` and `URL=` in `setup.sh`, then reset |
