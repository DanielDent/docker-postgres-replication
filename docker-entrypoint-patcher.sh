#!/usr/bin/env bash

set -e

if [ -e "/etc/alpine-release" ]; then
    sed -i 's/gosu/su-exec/g' /usr/local/bin/docker-entrypoint.sh
fi

POSTGRES_VERSION=$(postgres --version)

if echo $POSTGRES_VERSION | grep -e "^postgres (PostgreSQL) 9\."; then
    sed -i -e 's/WALDIR/XLOGDIR/g' \
           -e 's/waldir/xlogdir/g' \
        /usr/local/bin/docker-entrypoint.sh
fi
