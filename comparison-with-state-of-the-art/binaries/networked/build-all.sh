#!/usr/bin/env bash

set -eu
set -o pipefail

cmds=""
for dir in $PWD/*; do
    if [[ -d $dir ]]; then
        cmds+="./build.sh $(basename $dir) $1\n"
    fi
done

no_parallel=""
if [[ "$1" == "deps" ]]; then
    # deps stage uses apt, which does not allow parallel execution.
    no_parallel="-j1"
fi

echo -e $cmds |  parallel $no_parallel --bar -k