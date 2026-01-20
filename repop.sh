#!/bin/sh
# Repopulate base log files from .000 rotated logs
# Run inside test/logs

set -e

find . -type f -name '*.000' | while read f; do
    base="${f%.000}"

    # Only create base if it doesn't already exist
    if [ ! -e "$base" ]; then
        echo "Creating base log: $base"
        cp -- "$f" "$base"
    fi
done
