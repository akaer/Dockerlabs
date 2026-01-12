#!/usr/bin/env bash

# Check for required commands
for cmd in unix2dos docker; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "Error: $cmd is not installed!"
        exit 1
    fi
done

INCLUDEFILE="$(dirname "$0")/env.demo"
readonly INCLUDEFILE

if [[ -f "$INCLUDEFILE" ]]; then
    # shellcheck source=./env.demo
    source "$INCLUDEFILE"
fi

cp -f "$INCLUDEFILE" scripts/env.ps1

# Convert docker compose env file to a sourceable file by PowerShell
sed -i -e "/=/ s|^|\$|g" \
       -e "/=/ s|=|=\'|g" \
       -e "/=/ s|$|'|g" \
       -e "/:/ s|:|-|g" \
       scripts/env.ps1
unix2dos -m scripts/env.ps1

helper/create_certificates.sh

docker compose --env-file "$INCLUDEFILE" up -d

exit 0
