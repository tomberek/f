#!/usr/bin/env bash

set -euo pipefail
INPUT="$1"
while read -r line; do
    echo "$line"
    if pub=$(echo -n "$line" | grep -oP ".*Public key: \K\w+" ); then
        pubTrim=$(echo -n "$pub" | tail -c 10)
    else
        continue
    fi
    echo "continue"
    packetnum=0
    while read -r line; do
        sleep 0.2
        echo "sent $packetnum . $line" >&2
        cp ./rock "./rock.$pubTrim.$packetnum.$line"
        { "./rock.$pubTrim.$packetnum.$line" || true ; } 2>/dev/null >/dev/null
        rm "./rock.$pubTrim.$packetnum.$line"
        packetnum=$(( packetnum + 1 ))
    done < <(printf "%s" "$INPUT" | age -r "$pub" -a | tr '/' '%')
done < <(nix build .#paper -L 2>&1 )

