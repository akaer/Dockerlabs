#!/usr/bin/env bash

INCLUDEFILE="$(dirname "$0")/demo.env"
readonly INCLUDEFILE

if [[ -f "$INCLUDEFILE" ]]; then
    # shellcheck source=./env.demo
    source "$INCLUDEFILE"
fi

docker compose --env-file "$INCLUDEFILE" down

