#!/usr/bin/env bash

docker compose --env-file env.demo down -v

docker rmi mssql-2022:latest || true

rm -f scripts/env.ps1
rm -rf scripts/certs
rm -f db/mssql.crt
rm -f db/mssql.key
