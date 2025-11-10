#!/usr/bin/env bash

docker compose --env-file env.demo stop

sudo killall vde_switch || true

