#!/usr/bin/env bash

set -eu

function build_generator {
    rm -rf generator
    cp -r src generator

    pushd generator > /dev/null
    export FT_CALL_INJECTION=1
    export FT_HOOK_INS=branch,load,store,select,switch

    export CC=/home/user/fuzztruction/generator/pass/fuzztruction-source-clang-fast
    export CXX=/home/user/fuzztruction/generator/pass/fuzztruction-source-clang-fast++

    ./auto/configure --with-cc-opt='-DNDEBUG -DFT_FUZZING -DFT_GENERATOR' --without-quic_bpf_module --with-http_ssl_module --with-http_v2_module --with-http_v3_module --with-openssl=/home/user/fuzztruction/fuzztruction-experiments/comparison-with-state-of-the-art/binaries/networked/openssl/consumer/openssl/
    make -j

    popd > /dev/null
}

function build_consumer {
    mkdir -p consumer
    rm -rf consumer
    cp -r src consumer

    pushd consumer > /dev/null
    export AFL_LLVM_LAF_SPLIT_SWITCHES=1
    export AFL_LLVM_LAF_TRANSFORM_COMPARES=1
    export AFL_LLVM_LAF_SPLIT_COMPARES=1

    export CC=afl-clang-fast
    export CXX=afl-clang-fast++

    ./auto/configure --with-cc-opt='-g -O3 -fsanitize=address -DNGX_DEBUG_PALLOC=1 -DFT_FUZZING -DFT_CONSUMER' --with-debug  --with-ld-opt=-fsanitize=address --without-quic_bpf_module --with-http_ssl_module --with-http_v2_module --with-http_v3_module --with-openssl=/home/user/fuzztruction/fuzztruction-experiments/comparison-with-state-of-the-art/binaries/networked/openssl/consumer/openssl/
    make -j

    popd > /dev/null
}

function build_consumer_llvm_cov {
    rm -rf consumer_llvm_cov
    cp -r src consumer_llvm_cov
    cd consumer_llvm_cov

    export AFL_LLVM_LAF_SPLIT_SWITCHES=1
    export AFL_LLVM_LAF_TRANSFORM_COMPARES=1
    export AFL_LLVM_LAF_SPLIT_COMPARES=1

    export CC=afl-clang-fast
    export CXX=afl-clang-fast++

    ./auto/configure --with-cc-opt='-g -O0 -fsanitize=address -DNGX_DEBUG_PALLOC=1 -fprofile-instr-generate -fcoverage-mapping -DFT_COVERAGE -DFT_FUZZING -DFT_CONSUMER' --with-ld-opt='-fsanitize=address -fprofile-instr-generate -fcoverage-mapping' --without-quic_bpf_module --with-http_ssl_module --with-http_v2_module --with-http_v3_module --with-openssl=/home/user/fuzztruction/fuzztruction-experiments/comparison-with-state-of-the-art/binaries/networked/openssl/consumer_llvm_cov/openssl/
    make -j
}

function build_consumer_afl_net {
    rm -rf consumer_afl_net
    cp -r src consumer_afl_net
    cd consumer_afl_net

    export CC=/competitors/aflnet/afl-clang-fast
    export CXX=/competitors/aflnet/afl-clang-fast++
    ./auto/configure --with-cc-opt='-g -O3 -fsanitize=address -DNGX_DEBUG_PALLOC=1 -fprofile-instr-generate -fcoverage-mapping -DFT_FUZZING -DFT_CONSUMER' --with-ld-opt=-fsanitize=address --without-quic_bpf_module --with-http_ssl_module --with-http_v2_module --with-http_v3_module
    make -j
}

function build_consumer_stateafl {
    rm -rf consumer_stateafl
    cp -r src consumer_stateafl
    pushd consumer_stateafl > /dev/null

    export CC=/competitors/stateafl/afl-clang-fast
    export CXX=/competitors/stateafl/afl-clang-fast++
    ./auto/configure --with-cc-opt='-g -O3 -fsanitize=address -DNGX_DEBUG_PALLOC=1 -fprofile-instr-generate -fcoverage-mapping -DFT_FUZZING -DFT_CONSUMER' --with-ld-opt=-fsanitize=address --without-quic_bpf_module --with-http_ssl_module --with-http_v2_module --with-http_v3_module
    make -j
}


function build_consumer_sgfuzz {
    rm -rf consumer_sgfuzz
    cp -r src consumer_sgfuzz
    cd consumer_sgfuzz

    export CC=clang
    export CXX=clang++
    export CFLAGS="-g -O3 -fsanitize=address -fsanitize=fuzzer-no-link -DSGFUZZ -v -Wno-int-conversion -v"
    export CXXFLAGS="-g -O3 -fsanitize=address -fsanitize=fuzzer-no-link -DSGFUZZ -v -Wno-int-conversion -v"
    export LDFLAGS="-fsanitize=address -fsanitize=fuzzer-no-link"

    python3 /competitors/SGFuzz/sanitizer/State_machine_instrument.py . #  -b <(echo "EC_Normal\nOFFilename\nnptr")

    ./auto/configure --with-cc-opt='-g -O3 -fsanitize=address -DNGX_DEBUG_PALLOC=1 -fprofile-instr-generate -fcoverage-mapping -DSGFUZZ -DFT_FUZZING -DFT_CONSUMER' --with-ld-opt=-fsanitize=address --without-quic_bpf_module --with-http_ssl_module --with-http_v2_module --with-http_v3_module
    make -j

    set +e
    make -j
    set -e

    #clang  -fsanitize=address -DSGFUZZ  -fsanitize=fuzzer -lsFuzzer -lhfnetdriver -lhfcommon


    echo "done!"
}

function install_dependencies {
    sudo apt install -y libev-dev
}

function get_source {
    if [[ ! -d "src" ]]; then
        git clone https://github.com/nginx/nginx.git src || true
    fi
    cd src
    git checkout 6b1bb998c96278a56d767bc23520c385ab9f3038
    git apply ../fuzzing.patch
}
