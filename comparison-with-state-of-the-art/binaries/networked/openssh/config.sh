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
    export CFLAGS="-g -O3 -DNDEBUG -D_FORTIFY_SOURCE=0"
    export CXXFLAGS="-g -O3 -DNDEBUG -D_FORTIFY_SOURCE=0"

    cd openssl
    ./config -d shared no-threads no-tests no-asm no-cached-fetch no-async enable-tls1_3 --prefix=$PWD/installed
    sed -i 's/CC=$(CROSS_COMPILE)gcc.*/CC=\/home\/user\/fuzztruction\/generator\/pass\/fuzztruction-source-clang-fast/g' Makefile
    sed -i 's/CXX=$(CROSS_COMPILE)g++.*/CXX=\/home\/user\/fuzztruction\/generator\/pass\/fuzztruction-source-clang-fast++/g' Makefile
    sed -i 's/CFLAGS=.*/CFLAGS=-O3 -g -DNDEBUG -DFUZZING_BUILD_MODE_UNSAFE_FOR_PRODUCTION -DFT_FUZZING -DFT_GENEARTOR/g' Makefile
    sed -i 's/CXXFLAGS=.*/CXXFLAGS=-O3 -DNDEBUG -g -DFUZZING_BUILD_MODE_UNSAFE_FOR_PRODUCTION -DFT_FUZZING -DFT_GENEARTOR/g' Makefile
    LDCMD=/home/user/fuzztruction/generator/pass/fuzztruction-source-clang-fast bear -- make -j
    make install
    cp -r installed/lib64 installed/lib
    cd ..

    export CFLAGS="-g -O3 -DFT_FUZZING -DFT_GENEARTOR -DNDEBUG -D_FORTIFY_SOURCE=0 -L $PWD/openssl/installed/lib -I $PWD/openssl/installed/include"
    export CXXFLAGS="-g -O3 -DFT_FUZZING -DFT_GENEARTOR -DNDEBUG -D_FORTIFY_SOURCE=0 -L $PWD/openssl/installed/lib -I $PWD/openssl/installed/include"
    export LD_LIBRARY_PATH="$PWD/openssl/installed/lib64"
    export PKG_CONFIG_PATH="$PWD/openssl/installed/lib64/pkgconfig"

    autoreconf
    ./configure --without-sandbox --without-bsd-auth --with-ssl-dir=$PWD/openssl/installed
    make -j

    rm -rf ./openssl/fuzz
    rm -rf ./openssl/test
    rm -rf ./openssl/.git

    popd > /dev/null
}

function build_consumer {
    rm -rf consumer
    cp -r src consumer

    pushd consumer > /dev/null

    export AFL_LLVM_LAF_SPLIT_SWITCHES=1
    export AFL_LLVM_LAF_TRANSFORM_COMPARES=1
    export AFL_LLVM_LAF_SPLIT_COMPARES=1

    export CC=afl-clang-fast
    export CXX=afl-clang-fast++
    export CFLAGS="-g -O3 -fsanitize=address"
    export CXXFLAGS="-g -O3 -fsanitize=address"
    export LDFLAGS="-fsanitize=address"

    cd openssl
    ./config -d enable-asan --prefix=$PWD/installed
    sed -i 's/CC=$(CROSS_COMPILE)gcc.*/CC=afl-clang-fast/g' Makefile
    sed -i 's/CXX=$(CROSS_COMPILE)g++.*/CXX=afl-clang-fast++/g' Makefile
    sed -i 's/CFLAGS=.*/CFLAGS=-O3 -g -fsanitize=address -DFT_FUZZING -DFT_GENEARTOR/g' Makefile
    sed -i 's/CXXFLAGS=.*/CXXFLAGS=-O3 -g -fsanitize=address -DFT_FUZZING -DFT_GENEARTOR/g' Makefile
    LDCMD=afl-clang-fast bear -- make -j
    make install
    cd ..

    export CFLAGS="-g -O3 -fsanitize=address -DFT_FUZZING -DFT_GENEARTOR -L $PWD/openssl/installed/lib64 -I $PWD/openssl/installed/include"
    export CXXFLAGS="-g -O3 -fsanitize=address -DFT_FUZZING -DFT_GENEARTOR -L $PWD/openssl/installed/lib64 -I $PWD/openssl/installed/include"
    export LD_LIBRARY_PATH="$PWD/openssl/installed/lib64"
    export PKG_CONFIG_PATH="$PWD/openssl/installed/lib64/pkgconfig"

    autoreconf
    ./configure --without-sandbox --without-bsd-auth --with-ssl-dir=$PWD/openssl/installed
    make -j

    rm -rf ./openssl/fuzz
    rm -rf ./openssl/test
    rm -rf ./openssl/.git

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
    export CXXFLAGS="-g -O0 -fsanitize=address -DFT_FUZZING -DFT_CONSUMER -fprofile-instr-generate -fcoverage-mapping"
    export LDFLAGS="-fprofile-instr-generate -fcoverage-mapping -fsanitize=address"

    cd openssl
    ./config -d enable-asan --prefix=$PWD/installed
    sed -i 's/CC=$(CROSS_COMPILE)gcc.*/CC=afl-clang-fast/g' Makefile
    sed -i 's/CXX=$(CROSS_COMPILE)g++.*/CXX=afl-clang-fast++/g' Makefile
    sed -i 's/CFLAGS=.*/CFLAGS=-O0 -g -fsanitize=address -fprofile-instr-generate -fcoverage-mapping -DFT_FUZZING -DFT_GENEARTOR/g' Makefile
    sed -i 's/CXXFLAGS=.*/CXXFLAGS=-O0 -g -fsanitize=address -fprofile-instr-generate -fcoverage-mapping -DFT_FUZZING -DFT_GENEARTOR/g' Makefile
    LDCMD=afl-clang-fast bear -- make -j
    make install
    cd ..

    export CFLAGS="-g -O0 -fsanitize=address -DFT_FUZZING -DFT_CONSUMER -L $PWD/openssl/installed/lib64 -I $PWD/openssl/installed/include"
    export CXXFLAGS="-g -O0 -fsanitize=address -DFT_FUZZING -DFT_CONSUMER -L $PWD/openssl/installed/lib64 -I $PWD/openssl/installed/include"
    export LD_LIBRARY_PATH="$PWD/openssl/installed/lib64"
    export PKG_CONFIG_PATH="$PWD/openssl/installed/lib64/pkgconfig"

    autoreconf
    ./configure --without-sandbox --without-bsd-auth --with-ssl-dir=$PWD/openssl/installed
    make -j

    rm -rf ./openssl/fuzz
    rm -rf ./openssl/test
    rm -rf ./openssl/.git
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

    ./configure
    make -j

    rm -rf ./openssl/fuzz
    rm -rf ./openssl/test
    rm -rf ./openssl/.git
}

function build_consumer_stateafl {
    rm -rf consumer_stateafl
    cp -r src consumer_stateafl
    cd consumer_stateafl

    export CC=/competitors/stateafl/afl-clang-fast
    export CXX=/competitors/stateafl/afl-clang-fast++
    export CFLAGS="-g -O3 -fsanitize=address -DFT_FUZZING -DFT_CONSUMER"
    export CXXFLAGS="-g -O3 -fsanitize=address -DFT_FUZZING -DFT_CONSUMER"
    export LDFLAGS="-fsanitize=address"

    ./configure
    make -j

    rm -rf ./openssl/fuzz
    rm -rf ./openssl/test
    rm -rf ./openssl/.git
}

function build_consumer_sgfuzz {
    rm -rf consumer_sgfuzz
    cp -r src consumer_sgfuzz
    cd consumer_sgfuzz

    export CC=clang
    export CXX=clang++
    export CFLAGS="-g -O3 -fsanitize=address -fsanitize=fuzzer-no-link -DFT_FUZZING -DFT_CONSUMER -DSGFUZZ"
    export CXXFLAGS="-g -O3 -fsanitize=address -fsanitize=fuzzer-no-link -DFT_FUZZING -DFT_CONSUMER -DSGFUZZ"
    export LDFLAGS="-fsanitize=address -fsanitize=fuzzer-no-link"

    ./configure

    set +e
    make -j
    set -e

    cd pjsip-apps/build
    clang -o ../bin/samples/x86_64-unknown-linux-gnu/siprtp \
    output/sample-x86_64-unknown-linux-gnu/siprtp.o -L/home/user/fuzztruction/fuzztruction-experiments/comparison-with-state-of-the-art/binaries/networked/pjproject/consumer_sgfuzz/pjlib/lib -L/home/user/fuzztruction/fuzztruction-experiments/comparison-with-state-of-the-art/binaries/networked/pjproject/consumer_sgfuzz/pjlib-util/lib -L/home/user/fuzztruction/fuzztruction-experiments/comparison-with-state-of-the-art/binaries/networked/pjproject/consumer_sgfuzz/pjnath/lib -L/home/user/fuzztruction/fuzztruction-experiments/comparison-with-state-of-the-art/binaries/networked/pjproject/consumer_sgfuzz/pjmedia/lib -L/home/user/fuzztruction/fuzztruction-experiments/comparison-with-state-of-the-art/binaries/networked/pjproject/consumer_sgfuzz/pjsip/lib -L/home/user/fuzztruction/fuzztruction-experiments/comparison-with-state-of-the-art/binaries/networked/pjproject/consumer_sgfuzz/third_party/lib             -fsanitize=address -fsanitize=fuzzer-no-link -lpjsua-x86_64-unknown-linux-gnu -lpjsip-ua-x86_64-unknown-linux-gnu -lpjsip-simple-x86_64-unknown-linux-gnu -lpjsip-x86_64-unknown-linux-gnu -lpjmedia-codec-x86_64-unknown-linux-gnu -lpjmedia-videodev-x86_64-unknown-linux-gnu -lpjmedia-audiodev-x86_64-unknown-linux-gnu -lpjmedia-x86_64-unknown-linux-gnu -lpjnath-x86_64-unknown-linux-gnu -lpjlib-util-x86_64-unknown-linux-gnu -lsrtp-x86_64-unknown-linux-gnu -lresample-x86_64-unknown-linux-gnu -lgsmcodec-x86_64-unknown-linux-gnu -lspeex-x86_64-unknown-linux-gnu -lilbccodec-x86_64-unknown-linux-gnu -lg7221codec-x86_64-unknown-linux-gnu -lyuv-x86_64-unknown-linux-gnu -lwebrtc-x86_64-unknown-linux-gnu  -lpj-x86_64-unknown-linux-gnu -lssl -lcrypto -luuid -lm -lrt -lpthread -lsFuzzer -lhfnetdriver -lhfcommon -lstdc++ -fsanitize=fuzzer -fsanitize=address -DSGFUZZ

    rm -rf ./openssl/fuzz
    rm -rf ./openssl/test
    rm -rf ./openssl/.git

    echo "done!"
}


function build_vanilla {
    mkdir -p vanilla
    rm -rf vanilla/*
    cp -r src/openssh-portable vanilla/
    pushd vanilla/openssh-portable > /dev/null
    ./config -d shared no-threads
    make -j || true
    make
    popd > /dev/null
}

function install_dependencies {
    echo "No dependencies"
}

function get_source {
    if [[ ! -d "src" ]]; then
        git clone https://github.com/openssh/openssh-portable.git src
    fi
    cd src
    git checkout V_9_7_P1
    git apply ../fuzzing.patch

    git clone https://github.com/openssl/openssl.git
    cd openssl
    git checkout openssl-3.3.0
}
