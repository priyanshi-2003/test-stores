# OpenCart test store

A real OpenCart shop in Docker, for testing leonardo executors against its API.

| | |
|---|---|
| Shop | http://localhost:8084 |
| Admin | http://localhost:8084/admin, login `admin` / `Admin12345!` |
| Versions | OpenCart 4.1.0.4 (official release), PHP 8.3 + Apache, MariaDB 11.4 |
| Containers | `opencart-opencart-1`, `opencart-db-1` |
| Data | Docker volumes `opencart_db`, `opencart_html` |

These are local test passwords only.

## Run
```bash
chmod +x setup.sh oc-api.sh
./setup.sh            # first run ~5 min; later runs just start it
```
Use `sudo ./setup.sh` (and `sudo ./oc-api.sh`) if your user isn't in the `docker` group.

On the first run it:
- builds the OpenCart image from the official 4.1.0.4 zip;
- starts the 2 containers;
- installs OpenCart with its demo products;
- allows this machine's IP to use the API;
- saves the API key to `credentials.env`;
- makes one signed API call as a test.

| Command | Does |
|---|---|
| `./setup.sh status` | show the containers |
| `./setup.sh creds` | print the API key |
| `./setup.sh test` | re-run the API check |
| `./setup.sh allow-ip <ip>` | let another machine (e.g. one running leonardo) call the API |
| `./setup.sh logs` | follow the logs |
| `./setup.sh stop` | stop (data kept; start again with `./setup.sh`) |
| `./setup.sh reset` | delete containers **and** data (asks first) |

## The API is different from the other stores
OpenCart 4.1 has **no open JSON API for products or orders**. Its API:
- only answers `index.php?route=api/order` (and `api/subscription`), with a `call=` parameter: `customer`, `cart`, `product_add`, `payment_address`, `shipping_address`, `shipping_methods`, `shipping_method`, `payment_methods`, `payment_method`, `confirm`, `history_add` …;
- needs **every call signed**: `signature = base64(HMAC-SHA1(api_key, route⏎call⏎username⏎host⏎/⏎store_id⏎language⏎currency⏎md5(POST body)⏎time⏎))`;
- rejects a `time` more than 450 seconds off the server's clock;
- only accepts callers whose IP is on the API user's list.

`oc-api.sh` does the signing for you:
```bash
./oc-api.sh cart                                   # read the cart
./oc-api.sh product_add product_id=40 quantity=1   # add a demo product (40 = iPhone)
./oc-api.sh cart
```

**For executors:** a template would have to compute this HMAC-SHA1 signature and the current time itself. Whether Temple can do that is the open question for OpenCart.

## Problems
| Problem | Fix |
|---|---|
| `permission denied ... docker.sock` | `sudo ./setup.sh`, or `sudo usermod -aG docker $USER` then log out and back in |
| Signed call returns 403 | Your IP isn't allowed. `./setup.sh logs` shows the caller IP; add it with `./setup.sh allow-ip <ip>`. Also check the machine's clock. |
| "OpenCart install did not finish" | Read the installer output above it, then `./setup.sh reset` and `./setup.sh` |
| Port 8084 in use | Change `"8084:80"` in `docker-compose.yml` and `URL=` in `setup.sh`, then reset |
