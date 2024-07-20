#!/usr/bin/env bash

set -eu

# Build all binaries in this project without any additional instrumentation
function build_generator {
    mkdir -p inputs
    rm -rf generator/
    cp -r src generator
    cd generator

    export FT_HOOK_INS=call,branch,store,select,switch
    export FT_CALL_INJECTION=1
    export CC=/home/user/fuzztruction/generator/pass/fuzztruction-source-clang-fast
    export CXX=/home/user/fuzztruction/generator/pass/fuzztruction-source-clang-fast++

    export CFLAGS="-DFT_FUZZING -DNDEBUG -DFT_GENERATOR -g"
    export CXXFLAGS="-DFT_FUZZING -DNDEBUG -DFT_GENERATOR -g"

    ./configure --disable-tests --disable-doc
    make -j
}

# Build all binaries in this project as a fuzz target
function build_consumer {
    rm -rf consumer/
    cp -r src consumer
    cd consumer

    export AFL_LLVM_LAF_SPLIT_SWITCHES=1
    export AFL_LLVM_LAF_TRANSFORM_COMPARES=1
    export AFL_LLVM_LAF_SPLIT_COMPARES=1

    export CC="afl-clang-fast"
    export CXX="afl-clang-fast++"
    export CFLAGS="-g -O3 -fsanitize=address -DFT_FUZZING -DFT_CONSUMER"
    export CXXFLAGS="-g -O3 -fsanitize=address -DFT_FUZZING -DFT_CONSUMER"
    export LDFLAGS="-fsanitize=address"

    ./configure --disable-tests --disable-doc
    make -j
}

function build_consumer_llvm_cov {
    rm -rf consumer_llvm_cov
    cp -r src consumer_llvm_cov
    cd consumer_llvm_cov

    export CC=afl-clang-fast
    export CXX=afl-clang-fast++
    export CFLAGS="-g -O0 -DFT_FUZZING -DFT_CONSUMER -fsanitize=address -fprofile-instr-generate -fcoverage-mapping"
    export CXXFLAGS="-g -O0 -DFT_FUZZING -DFT_CONSUMER -fsanitize=address -fprofile-instr-generate -fcoverage-mapping"
    export LDFLAGS="-fsanitize=address -fprofile-instr-generate -fcoverage-mapping"

    ./configure --disable-tests --disable-doc --disable-shared --enable-static
    make -j
}

function build_consumer_afl_net {
    rm -rf consumer_afl_net
    cp -r src consumer_afl_net
    cd consumer_afl_net

    export CC=/competitors/aflnet/afl-clang-fast
    export CXX=/competitors/aflnet/afl-clang-fast++
    export CFLAGS="-g -O3 -fsanitize=address -DFT_FUZZING -DFT_CONSUMER"
    export CXXFLAGS="-g -O3 -fsanitize=address -DFT_FUZZING -DFT_CONSUMER"
    export LDFLAGS="-fsanitize=address"

    ./configure --disable-tests --disable-doc
    make -j
}

function build_consumer_stateafl {
    rm -rf consumer_stateafl
    cp -r src consumer_stateafl
    cd consumer_stateafl

    export ASAN_OPTIONS=detect_leaks=0
    export CC=/competitors/stateafl/afl-clang-fast
    export CXX=/competitors/stateafl/afl-clang-fast++
    export CFLAGS="-g -O3 -fsanitize=address -DFT_FUZZING -DFT_CONSUMER"
    export CXXFLAGS="-g -O3 -fsanitize=address -DFT_FUZZING -DFT_CONSUMER"
    export LDFLAGS="-fsanitize=address"

    ./configure --disable-tests --disable-doc
    make -j
}

function build_consumer_sgfuzz {
    rm -rf consumer_sgfuzz
    cp -r src consumer_sgfuzz
    cd consumer_sgfuzz

    export ASAN_OPTIONS=detect_leaks=0
    export CC=clang
    export CXX=clang++
    export CFLAGS="-g -O3 -fsanitize=fuzzer-no-link -fPIC -fsanitize=address -DFT_FUZZING -DFT_CONSUMER -DSGFUZZ -Wno-int-conversion -v"
    export CXXFLAGS="-g -O3 -fsanitize=fuzzer-no-link -fPIC -fsanitize=address -DFT_FUZZING -DFT_CONSUMER -DSGFUZZ -Wno-int-conversion -v"
    export LDFLAGS="-fsanitize=fuzzer-no-link -fPIC -fsanitize=address"

    python3 /competitors/SGFuzz/sanitizer/State_machine_instrument.py .

    ./configure --disable-tests --disable-doc
    # will fail because of missing main
    set +e
    make -j
    set -e

    cd src
    clang -o .libs/gnutls-serv -L/usr/lib/clang/17/lib/x86_64-unknown-linux-gnu -L/usr/bin/../lib/gcc/x86_64-linux-gnu/12 -L/usr/bin/../lib/gcc/x86_64-linux-gnu/12/../../../../lib64 -L/lib/x86_64-linux-gnu -L/lib/../lib64 -L/usr/lib/x86_64-linux-gnu -L/usr/lib/../lib64 -L/lib -L/usr/lib  /usr/lib/clang/17/lib/x86_64-unknown-linux-gnu/libclang_rt.asan_static.a  /usr/lib/clang/17/lib/x86_64-unknown-linux-gnu/libclang_rt.asan.a serv.o udp-serv.o common.o ../lib/.libs/libgnutls.so ./.libs/libcmd-serv.a ../gl/.libs/libgnu.a gl/.libs/libgnu_gpl.a  -lpthread -lrt -lm -ldl -lresolv -lgcc  -lgcc_s  -lc -lgcc -lsFuzzer -lhfnetdriver -lhfcommon -lstdc++ -fsanitize=fuzzer -fsanitize=address

    echo "done"
}

function install_dependencies {
    sudo apt-get install -y dash git-core autoconf libtool gettext autopoint
    sudo apt-get install -y automake python3 nettle-dev libp11-kit-dev libtspi-dev libunistring-dev
    sudo apt-get install -y libtasn1-bin libtasn1-6-dev libidn2-0-dev gawk gperf
    sudo apt-get install -y libtss2-dev libunbound-dev dns-root-data bison gtk-doc-tools
    sudo apt-get install -y texinfo texlive texlive-plain-generic texlive-extra-utils libprotobuf-c1 libev4 libev-dev
}

function get_source {
    git clone https://github.com/gnutls/gnutls.git src
    cd src
    git checkout 3.8.2
    git apply ../fuzzing.patch
    ./bootstrap
    return 0
}
