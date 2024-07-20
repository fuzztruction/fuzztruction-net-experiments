#!/usr/bin/env bash

set -eu

# Build all binaries in this project without any additional instrumentation
function build_generator {
    rm -rf generator/
    cp -r src generator
    cd generator

    export FT_CALL_INJECTION=1
    # Target is too large for instrumenting all instructions.
    export FT_HOOK_INS=store:25,select,switch
    export CC=/home/user/fuzztruction/generator/pass/fuzztruction-source-clang-fast
    export CXX=/home/user/fuzztruction/generator/pass/fuzztruction-source-clang-fast++

    export CFLAGS="-DNDEBUG -DFT_FUZZING -DFT_GENERATOR -g"
    export CXXFLAGS="-DNDEBUG -DFT_FUZZING -DFT_GENERATOR -g"

    ./configure --with-static-modules=ALL #--nonshared-binary=smbd/smbd,client/smbclient
    make -j smbd/smbd client/smbclient
}

# Build all binaries in this project as a fuzz target
function build_consumer {
    rm -rf consumer
    cp -r src consumer
    cd consumer

    export AFL_LLVM_LAF_SPLIT_SWITCHES=1
    export AFL_LLVM_LAF_TRANSFORM_COMPARES=1
    export AFL_LLVM_LAF_SPLIT_COMPARES=1

    export ASAN_OPTIONS="detect_leaks=0:abort_on_error=0"
    export CC="/usr/local/bin/afl-clang-fast"
    export CXX="/usr/local/bin/afl-clang-fast++"
    export CFLAGS="-g -O3 -fsanitize=address -DFT_FUZZING -DFT_CONSUMER -DHAVE_DISABLE_FAULT_HANDLING"
    export CXXFLAGS="-g -O3 -fsanitize=address -DFT_FUZZING -DFT_CONSUMER -DHAVE_DISABLE_FAULT_HANDLING"
    export LDFLAGS="-fsanitize=address"

    #./configure --with-static-modules=ALL #--nonshared-binary=smbd/smbd,client/smbclient
    ./configure --nonshared-binary=smbd/smbd,client/smbclient
    make -j smbd/smbd client/smbclient
}

function build_consumer_llvm_cov {
    rm -rf consumer_llvm_cov
    cp -r src consumer_llvm_cov
    cd consumer_llvm_cov

    export AFL_LLVM_LAF_SPLIT_SWITCHES=1
    export AFL_LLVM_LAF_TRANSFORM_COMPARES=1
    export AFL_LLVM_LAF_SPLIT_COMPARES=1

    export ASAN_OPTIONS="detect_leaks=0:abort_on_error=0"
    export CC="/usr/local/bin/afl-clang-fast"
    export CXX="/usr/local/bin/afl-clang-fast++"
    export CFLAGS="-g -O0 -DFT_FUZZING -DFT_CONSUMER -fsanitize=address -fprofile-instr-generate -fcoverage-mapping -DHAVE_DISABLE_FAULT_HANDLING"
    export CXXFLAGS="-g -O0 -DFT_FUZZING -DFT_CONSUMER -fsanitize=address -fprofile-instr-generate -fcoverage-mapping -DHAVE_DISABLE_FAULT_HANDLING"
    export LDFLAGS="-fsanitize=address -fprofile-instr-generate -fcoverage-mapping"

    ./configure --nonshared-binary=smbd/smbd,client/smbclient
    make -j smbd/smbd client/smbclient
}

function build_consumer_afl_net {
    rm -rf consumer_afl_net
    cp -r src consumer_afl_net
    cd consumer_afl_net

    export ASAN_OPTIONS="detect_leaks=0:abort_on_error=0"
    export CC=/competitors/aflnet/afl-clang-fast
    export CXX=/competitors/aflnet/afl-clang-fast++
    export CFLAGS="-g -O3 -fsanitize=address -DFT_FUZZING -DFT_CONSUMER -DHAVE_DISABLE_FAULT_HANDLING"
    export CXXFLAGS="-g -O3 -fsanitize=address -DFT_FUZZING -DFT_CONSUMER -DHAVE_DISABLE_FAULT_HANDLING"
    export LDFLAGS="-fsanitize=address"

    ./configure --with-static-modules=ALL #--nonshared-binary=smbd/smbd,client/smbclient
    make -j smbd/smbd client/smbclient
}

function build_consumer_stateafl {
    rm -rf consumer_stateafl
    cp -r src consumer_stateafl
    cd consumer_stateafl

    export FT_SKIP_WRITEV=1
    export ASAN_OPTIONS="detect_leaks=0:abort_on_error=0"
    export CC=/competitors/stateafl/afl-clang-fast
    export CXX=/competitors/stateafl/afl-clang-fast++
    export CFLAGS="-g -O3 -fsanitize=address -DFT_FUZZING -DFT_CONSUMER -DHAVE_DISABLE_FAULT_HANDLING"
    export CXXFLAGS="-g -O3 -fsanitize=address -DFT_FUZZING -DFT_CONSUMER -DHAVE_DISABLE_FAULT_HANDLING"
    export LDFLAGS="-fsanitize=address"

    ./configure --with-static-modules=ALL #--nonshared-binary=smbd/smbd,client/smbclient
    make -j smbd/smbd client/smbclient
}

function build_consumer_sgfuzz {
    rm -rf consumer_sgfuzz
    cp -r src consumer_sgfuzz
    cd consumer_sgfuzz

    echo "[!] Not supported"

    # export ASAN_OPTIONS="detect_leaks=0:abort_on_error=0"
    # export CC=clang
    # export CXX=clang++
    # export CFLAGS="-g -O3 -fsanitize=fuzzer-no-link -DFT_FUZZING -DFT_CONSUMER -DSGFUZZ -DHAVE_DISABLE_FAULT_HANDLING"
    # export CXXFLAGS="-g -O3 -fsanitize=fuzzer-no-link -DFT_FUZZING -DFT_CONSUMER -DSGFUZZ -DHAVE_DISABLE_FAULT_HANDLING"
    # export LDFLAGS="-fsanitize=fuzzer-no-link"

    # ./configure --with-static-modules=ALL #--nonshared-binary=smbd/smbd,client/smbclient

    # set +e
    # make -j smbd/smbd client/smbclient
    # set -e
}

function install_dependencies {
    cd src && sudo ./bootstrap/generated-dists/ubuntu2204/bootstrap.sh
}

function get_source {
    if [[ ! -d "src" ]]; then
        git clone https://github.com/samba-team/samba.git src
    fi
    cd src
    git checkout samba-4.19.4
    git apply ../fuzzing.patch
}
