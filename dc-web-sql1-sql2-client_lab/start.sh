#!/usr/bin/env bash

# Check for required commands
for cmd in docker vde_switch; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "Error: $cmd is not installed!"
        exit 1
    fi
done

sudo vde_switch -d -s /tmp/vde_switch.sock -t vde_tap0 -M /tmp/vde_mgmt.sock

docker compose --env-file env.demo start

