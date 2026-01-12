#!/usr/bin/env bash

# Check for required commands
for cmd in docker; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "Error: $cmd is not installed!"
        exit 1
    fi
done

docker compose --env-file env.demo start

