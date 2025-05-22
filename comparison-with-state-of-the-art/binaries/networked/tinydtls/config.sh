#!/usr/bin/env bash

set -eu

function build_generator {
    rm -rf generator
    cp -r src generator
    cd generator

    export FT_HOOK_INS=branch,store,select,switch
    export FT_CALL_INJECTION=1
    export CC=/home/user/fuzztruction/generator/pass/fuzztruction-source-clang-fast
    export CXX=/home/user/fuzztruction/generator/pass/fuzztruction-source-clang-fast++

    export CFLAGS="-DFT_FUZZING -DNDEBUG -DFT_GENERATOR"
    export CXXFLAGS="-DFT_FUZZING -DNDEBUG -DFT_GENERATOR"

    cd tests
    make clean
    make ../libtinydtls.a
    make
    cd ..
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
    export CFLAGS="-g -fsanitize=address -O3 -DFT_FUZZING -DFT_CONSUMER"
    export CXXFLAGS="-g -fsanitize=address -O3 -DFT_FUZZING -DFT_CONSUMER"
    export LDFLAGS="-fsanitize=address"

    cd tests
    make clean
    make ../libtinydtls.a
    make

    cd ..

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
    export CFLAGS="-g -O0 -fsanitize=address -DFT_FUZZING -DFT_CONSUMER -fprofile-instr-generate -fcoverage-mapping"
    export CXXFLAGS="-g -O0  -fsanitize=address -DFT_FUZZING -DFT_CONSUMER -fprofile-instr-generate -fcoverage-mapping"
    export LDFLAGS="-fsanitize=address -fprofile-instr-generate -fcoverage-mapping"

    cd tests
    make clean
    make ../libtinydtls.a
    make
    cd ..
}

function build_consumer_afl_net {
    echo "TBA"
}

function build_consumer_stateafl {
    echo "TBA"
}


function build_consumer_sgfuzz {
    echo "TBA"
}

function install_dependencies {
    echo "No dependencies"
}

function get_source {
    if [[ ! -d "src" ]]; then
        git clone https://github.com/assist-project/tinydtls-fuzz.git src
    fi
    cd src
    git checkout 06995d4
}
