#!/usr/bin/env bash

if [[ -f ./env.demo ]]; then
    . ./env.demo
fi

docker compose --env-file env.demo restart
