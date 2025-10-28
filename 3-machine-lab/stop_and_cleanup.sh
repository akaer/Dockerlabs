#!/usr/bin/env bash

# Set global script options
set -euo pipefail

docker compose --env-file env.demo down -v

sudo killall vde_switch || true
docker rmi mssql-2022:latest || true

rm -f scripts/env.ps1
rm -rf scripts/certs
rm -f db/mssql.crt
rm -f db/mssql.key
rm -f shared/state/*

