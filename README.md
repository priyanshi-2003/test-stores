# Test stores

Real e-commerce platforms in Docker, for testing leonardo's executor-based agentic commerce. Each folder is a separate store: run only the ones you need.

| Folder | Platform | URL | Containers | First run | Memory |
|---|---|---|---|---|---|
| `woocommerce/` | WooCommerce 11.3.1 on WordPress 7.1.5 | http://localhost:8081 | 2 | ~5 min | ~0.6 GB |
| `prestashop/` | PrestaShop 8.2.9 | http://localhost:8082 | 2 | ~5 min | ~0.7 GB |
| `magento/` | Magento Open Source 2.4.8-p5 | http://localhost:8083 | 3 | 20–30 min | ~3 GB |
| `opencart/` | OpenCart 4.1.0.4 | http://localhost:8084 | 2 | ~5 min | ~0.5 GB |

Admin logins are `admin` / `Admin12345!` everywhere; PrestaShop uses `admin@example.com`. These are local test passwords only.

## Use
```bash
cd woocommerce
chmod +x setup.sh
./setup.sh            # install the first time, start afterwards
```
Every folder has the same commands:

| Command | Does |
|---|---|
| `./setup.sh` | install on the first run, start on later runs |
| `./setup.sh status` | show this store's containers |
| `./setup.sh creds` | print this store's API credentials |
| `./setup.sh test` | check the store's API answers |
| `./setup.sh logs` | follow the logs |
| `./setup.sh stop` | stop (data kept) |
| `./setup.sh reset` | delete this store's containers and data (asks first) |

Use `sudo ./setup.sh` if your user isn't in the `docker` group (or run `sudo usermod -aG docker $USER` once, then log in again).

## Requirements
- Docker Engine + the compose plugin (`docker compose version`)
- `curl` and `openssl`
- Internet access on the first run
- RAM: ~5–6 GB for all four together; Magento alone ~3 GB

## Notes
- Containers restart by themselves (`restart: unless-stopped`) until you `./setup.sh stop` them. After a reboot they come back if Docker starts at boot.
- Each store has its own network and volumes, so resetting one never touches another.
- Each folder's `README.md` lists that store's API calls and the problems you might hit.
