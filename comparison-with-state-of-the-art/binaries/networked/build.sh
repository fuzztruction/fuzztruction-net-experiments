#!/usr/bin/env bash

set -eu
set -o pipefail

supported_targets="src deps generator consumer consumer-llvm-cov consumer-afl-net consumer-stateafl consumer-sgfuzz"

function usage () {
    echo "$0 <target-subfolder> <target> [target]..."
    echo "Valid targets are: $supported_targets"
}

function in_subshell () {
    (
        $1
    )
}

function check_config_exported_functions() {
    local failed=0
    local functions=(get_source install_dependencies build_generator build_consumer build_consumer_llvm_cov build_consumer_afl_net build_consumer_stateafl build_consumer_sgfuzz)
    for fn_name in ${functions[@]}; do
        if ! type $fn_name > /dev/null; then
            echo "[!] Target config does not define function $fn_name"
            failed=1
        fi
    done
    if [[ $failed -ne 0 ]]; then
        echo "[!] Config check failed! Please fix your config."
        exit 1
    fi
}

if [[ $# -lt 2 ]]; then
    usage
    exit 1
fi

path=$1
if [[ ! -d "$path" ]]; then
    echo "[!] Invalid directory: $path"
    exit 1
fi
cfg_path="$path/config.sh"
if [[ ! -f "$cfg_path" ]]; then
    echo "[!] Config could not be found at: $cfg_path"
    exit 1
fi

cd $path
source config.sh
check_config_exported_functions

while [[ $# -gt 1 ]]; do
    target=${2}

    case $target in
        source|src)
            in_subshell get_source
        ;;
        deps)
            in_subshell install_dependencies
        ;;
        generator)
            in_subshell build_generator
        ;;
        consumer)
            in_subshell build_consumer
        ;;
        consumer-llvm-cov)
            in_subshell build_consumer_llvm_cov
        ;;
        consumer-afl-net)
            in_subshell build_consumer_afl_net
        ;;
        consumer-stateafl)
            in_subshell build_consumer_stateafl
        ;;
        consumer-sgfuzz)
            in_subshell build_consumer_sgfuzz
        ;;
        all)
            in_subshell get_source
            in_subshell install_dependencies
            in_subshell build_generator
            in_subshell build_consumer
            in_subshell build_consumer_llvm_cov
            in_subshell build_consumer_afl_net
            in_subshell build_consumer_stateafl
            in_subshell build_consumer_sgfuzz
        ;;
        -h|--help)
            usage
            exit 0
        ;;
        *)
            echo "[!] Invalid target $target"
            echo "Valid targets are $supported_targets"
            exit 1
        ;;
    esac

    shift
done
