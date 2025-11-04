#!/usr/bin/env bash

# Set global script options
set -euo pipefail

docker compose --env-file env.demo down -v

sudo killall vde_switch || true

rm -f scripts/env.ps1
rm -rf scripts/certs
sudo rm -f shared/state/*

