#!/usr/bin/env bash
# Make a signed call to OpenCart 4.1's API (index.php?route=api/order).
#
#   ./oc-api.sh <call> [field=value ...]
#
#   ./oc-api.sh cart                                  # read the API session's cart
#   ./oc-api.sh product_add product_id=40 quantity=1  # POST fields
#
# Calls: customer, cart, product_add, payment_address, shipping_address, shipping_methods,
#        shipping_method, payment_methods, payment_method, extension, affiliate, confirm, history_add
#
# How OpenCart checks a call (catalog/controller/startup/api.php):
#   signature = base64( HMAC-SHA1( api_key,
#                 route \n call \n username \n HTTP_HOST \n path/ \n store_id \n language \n currency \n
#                 md5(http_build_query(POST)) \n time \n ) )
#   time must be within 450 s of the server clock, and the caller IP must be on the API user's list.
# Field values must already be URL-safe (they are signed exactly as sent).

set -euo pipefail
cd "$(dirname "$0")"
# shellcheck disable=SC1091
source credentials.env

call=${1:?usage: ./oc-api.sh <call> [field=value ...]}
shift

route=api/order
store_id=0
language=en-gb
currency=USD
host=${OPENCART_URL#*://}
host=${host%%/*}
time=$(date +%s)
post=$(IFS='&'; echo "$*")

if command -v md5sum >/dev/null; then
  post_md5=$(printf '%s' "$post" | md5sum | cut -d' ' -f1)
else
  post_md5=$(printf '%s' "$post" | md5 -q)
fi

signature=$(printf '%s\n' "$route" "$call" "$OPENCART_API_USERNAME" "$host" "/" \
                          "$store_id" "$language" "$currency" "$post_md5" "$time" \
            | openssl dgst -sha1 -hmac "$OPENCART_API_KEY" -binary | base64 \
            | sed 's/+/%2B/g; s/\//%2F/g; s/=/%3D/g')

url="$OPENCART_URL/index.php?route=$route&call=$call&username=$OPENCART_API_USERNAME"
url+="&store_id=$store_id&language=$language&currency=$currency&time=$time&signature=$signature"

if [ -n "$post" ]; then
  curl -s -m 30 --fail-with-body -X POST "$url" --data "$post"
else
  curl -s -m 30 --fail-with-body "$url"
fi
echo
