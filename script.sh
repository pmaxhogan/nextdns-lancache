#!/bin/bash

set -euo pipefail

git --version
jq --version

DELAY=".1"

fail () {
	echo "Error: $@"
	exit 1
}

check_var () {
  set +u
  local var_name=$1

  if [ -z "${!var_name}" ]; then
    printf 'Error: required environment variable "%s" is not set or empty.\n' "$var_name" >&2
    exit 1
  fi

  set -u
}

nextdns_api () {
	curl "https://api.nextdns.io/profiles/$1" -H "X-Api-Key: $NEXTDNS_API_KEY" "${@:2}"
}

sizeof () {
  wc -l $1 | cut -d' ' -f1
}

check_var CACHE_IP
check_var NEXTDNS_API_KEY

echo "NextDNS API key: ${NEXTDNS_API_KEY:0:2}...${NEXTDNS_API_KEY: -2}"
echo "-> Cache IP $CACHE_IP"

# Find nextdns profile
NEXTDNS_PROFILE=$(nextdns_api "" -s | jq -r '.data[0].id')
if [ -z "$NEXTDNS_PROFILE" ] ; then fail "No nextdns profile could be found" ; fi

echo "Found NextDNS Profile $NEXTDNS_PROFILE"


# Get cache domains

rm -rf cache-domains config.json

envsubst < config.template.json > config.json

git clone https://github.com/uklans/cache-domains
cp config.json cache-domains/scripts/config.json
cd cache-domains/scripts
./create-squid.sh
cp output/squid/monolithic.txt ../../domains.txt
cd ../../

rm -rf cache-domains config.json

# Organizing domains
cat domains.txt | sort -u | while read line ; do
	echo "${line#.}" >> domains.tmp.txt
done
rm domains.txt
mv domains.tmp.txt domains.txt

# Remove conflicting entries
echo "Removing conflicts"

set +o pipefail
nextdns_api "$NEXTDNS_PROFILE" -s | jq -r '.data.rewrites[] | [.id, .name, .content] | join ("\t")' | grep -wiFf "domains.txt" | grep -wivF "$CACHE_IP" | cut -f1 | tee | while read line ; do
	nextdns_api "$NEXTDNS_PROFILE/rewrites/"$line -s -X DELETE
	echo Deleted $line
	sleep $DELAY
done

set -o pipefail

# Add new entries (if needed)
echo "Finding existing entries"
set +o pipefail
nextdns_api "$NEXTDNS_PROFILE" -s | jq -r '.data.rewrites[] | [.name, .content] | join ("\t")' | grep -iFf "domains.txt" | cut -f1 | sort -u > existingdomains.txt
set -o pipefail

set +e
grep -xvFf existingdomains.txt domains.txt > newdomains.txt
set -e

echo "Adding $(sizeof newdomains.txt) domains (from $(sizeof domains.txt) total, $(sizeof existingdomains.txt) existing)"

rm existingdomains.txt

set +o pipefail
cat newdomains.txt | while read line; do
	nextdns_api "$NEXTDNS_PROFILE/rewrites" -s -X POST -H 'content-type: application/json' --data-raw '{"name":"'$line'","content":"'"$CACHE_IP"'"}' | jq -r '.data | [.name, .content] | join ("\t=>\t")'
	sleep $DELAY
done
set -o pipefail

rm newdomains.txt domains.txt

# DDNS
echo "Updating DDNS"
token=$(nextdns_api "$NEXTDNS_PROFILE" -s | jq -r '.data.setup.linkedIp.updateToken')
curl "https://link-ip.nextdns.io/$NEXTDNS_PROFILE/$token" -s

echo
echo
echo "✅ Setup complete!"
echo
echo "Configure nextdns at https://my.nextdns.io/$NEXTDNS_PROFILE/setup"
echo
echo "Set your DNS servers to:"
nextdns_api "$NEXTDNS_PROFILE" -s | jq -r '.data.setup.linkedIp.servers[]'
