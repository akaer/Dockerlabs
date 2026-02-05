#!/usr/bin/env bash

docker compose --env-file env.demo down -v

sudo killall vde_switch || true

rm -f scripts/env.ps1
rm -rf scripts/certs
sudo rm -f shared/state/*
