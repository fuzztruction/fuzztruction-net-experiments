#!/usr/bin/env bash

set -eu

function build_generator {
    mkdir -p inputs
    mkdir -p generator
    rm -rf generator
    cp -r src generator

    pushd generator > /dev/null
    export FT_CALL_INJECTION=1
    export FT_HOOK_INS=branch,load,store,select,switch

    export CC=/home/user/fuzztruction/generator/pass/fuzztruction-source-clang-fast
    export CXX=/home/user/fuzztruction/generator/pass/fuzztruction-source-clang-fast++
    export CFLAGS="-g -O3 -DNDEBUG -DFT_FUZZING -DFT_CONSUMER"
    export CXXFLAGS="-g -O3 -DNDEBUG -DFT_FUZZING -DFT_CONSUMER"

    cd wolfssl
    autoreconf -i
    ./configure --enable-all --enable-aesni --enable-keylog-export --disable-ech
    make -j
    cd ..

    export CMAKE_LIBRARY_PATH=$PWD/wolfssl/src/.libs
    export CMAKE_INCLUDE_PATH=$PWD/wolfssl

    cd nghttp3
    autoreconf -i
    ./configure
    make -j$(nproc) check
    cd ..

    export CMAKE_LIBRARY_PATH="$CMAKE_LIBRARY_PATH:$PWD/nghttp3/lib/.libs"
    export CMAKE_INCLUDE_PATH="$CMAKE_INCLUDE_PATH:$PWD/nghttp3/lib/includes"

    echo $CMAKE_LIBRARY_PATH

    mkdir build && cd build
    cmake .. -DENABLE_WOLFSSL=ON
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
    export CFLAGS="-g -O3 -fsanitize=address -DFT_FUZZING -DFT_CONSUMER"
    export CXXFLAGS="-g -O3 -fsanitize=address -DFT_FUZZING -DFT_CONSUMER"

    cd wolfssl
    autoreconf -i
    ./configure --enable-all --enable-aesni --enable-keylog-export --disable-ech
    make -j
    cd ..

    export CMAKE_LIBRARY_PATH=$PWD/wolfssl/src/.libs
    export CMAKE_INCLUDE_PATH=$PWD/wolfssl

    cd nghttp3
    autoreconf -i
    ./configure
    make -j$(nproc) check
    cd ..

    export CMAKE_LIBRARY_PATH="$CMAKE_LIBRARY_PATH:$PWD/nghttp3/lib/.libs"
    export CMAKE_INCLUDE_PATH="$CMAKE_INCLUDE_PATH:$PWD/nghttp3/lib/includes"

    echo $CMAKE_LIBRARY_PATH

    mkdir build && cd build
    cmake .. -DENABLE_WOLFSSL=ON
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
    export CFLAGS="-g -O0 -DFT_FUZZING -DFT_CONSUMER -fsanitize=address"
    export CXXFLAGS="-g -O0 -DFT_FUZZING -DFT_CONSUMER -fsanitize=address"
    export LDFLAGS=""

    cd wolfssl
    autoreconf -i
    ./configure --enable-all --enable-aesni --enable-keylog-export --disable-ech
    make -j
    cd ..

    export CMAKE_LIBRARY_PATH=$PWD/wolfssl/src/.libs
    export CMAKE_INCLUDE_PATH=$PWD/wolfssl

    cd nghttp3
    autoreconf -i
    ./configure
    make -j$(nproc) check
    cd ..

    export CMAKE_LIBRARY_PATH="$CMAKE_LIBRARY_PATH:$PWD/nghttp3/lib/.libs:$PWD/build/lib"
    export CMAKE_INCLUDE_PATH="$CMAKE_INCLUDE_PATH:$PWD/nghttp3/lib/includes"

    echo $CMAKE_LIBRARY_PATH

    mkdir build && cd build
    export CFLAGS="-g -O0 -DFT_FUZZING -DFT_CONSUMER -fsanitize=address -fprofile-instr-generate -fcoverage-mapping -v -L$PWD/lib"
    export CXXFLAGS="-g -O0  -DFT_FUZZING -DFT_CONSUMER -fsanitize=address -fprofile-instr-generate -fcoverage-mapping -v -L$PWD/lib"
    export LDFLAGS="-fprofile-instr-generate -fcoverage-mapping"

    cmake .. -DENABLE_WOLFSSL=ON -DENABLE_SHARED_LIB=OFF
    set +e
    make -j
    set -e

    cd examples
    make
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

    cd wolfssl
    autoreconf -i
    ./configure --enable-all --enable-aesni --enable-keylog-export --disable-ech
    make -j
    cd ..

    export CMAKE_LIBRARY_PATH=$PWD/wolfssl/src/.libs
    export CMAKE_INCLUDE_PATH=$PWD/wolfssl

    cd nghttp3
    autoreconf -i
    ./configure
    make -j$(nproc) check
    cd ..

    export CMAKE_LIBRARY_PATH="$CMAKE_LIBRARY_PATH:$PWD/nghttp3/lib/.libs"
    export CMAKE_INCLUDE_PATH="$CMAKE_INCLUDE_PATH:$PWD/nghttp3/lib/includes"

    echo $CMAKE_LIBRARY_PATH

    mkdir build && cd build
    cmake .. -DENABLE_WOLFSSL=ON
    make -j
}

function build_consumer_stateafl {
    rm -rf consumer_stateafl
    cp -r src consumer_stateafl
    pushd consumer_stateafl > /dev/null

    export CC=/competitors/stateafl/afl-clang-fast
    export CXX=/competitors/stateafl/afl-clang-fast++
    export CFLAGS="-g -O3 -fsanitize=address -DFT_FUZZING -DFT_CONSUMER"
    export CXXFLAGS="-g -O3 -fsanitize=address -DFT_FUZZING -DFT_CONSUMER"
    export LDFLAGS="-fsanitize=address"

    cd wolfssl
    autoreconf -i
    ./configure --enable-all --enable-aesni --enable-keylog-export --disable-ech
    make -j
    cd ..

    export CMAKE_LIBRARY_PATH=$PWD/wolfssl/src/.libs
    export CMAKE_INCLUDE_PATH=$PWD/wolfssl

    cd nghttp3
    autoreconf -i
    ./configure
    make -j$(nproc) check
    cd ..

    export CMAKE_LIBRARY_PATH="$CMAKE_LIBRARY_PATH:$PWD/nghttp3/lib/.libs"
    export CMAKE_INCLUDE_PATH="$CMAKE_INCLUDE_PATH:$PWD/nghttp3/lib/includes"

    echo $CMAKE_LIBRARY_PATH

    mkdir build && cd build
    cmake .. -DENABLE_WOLFSSL=ON
    make -j
}


function build_consumer_sgfuzz {
    rm -rf consumer_sgfuzz
    cp -r src consumer_sgfuzz
    cd consumer_sgfuzz

    export CC=clang
    export CXX=clang++
    export CFLAGS="-g -O3 -fsanitize=address -fsanitize=fuzzer-no-link -DSGFUZZ -v -Wno-int-conversion"
    export CXXFLAGS="-g -O3 -fsanitize=address -fsanitize=fuzzer-no-link -DSGFUZZ -v -Wno-int-conversion"
    export LDFLAGS="-fsanitize=address -fsanitize=fuzzer-no-link"

    python3 /competitors/SGFuzz/sanitizer/State_machine_instrument.py . #  -b <(echo "EC_Normal\nOFFilename\nnptr")

    mkdir build && cd build

    set +e
    cmake -G 'Unix Makefiles' -DQUIC_BUILD_TOOLS=ON -DQUIC_BUILD_SHARED=OFF ..
    cmake --build .
    set -e

    cd src/tools/sample
    clang -o ../../../bin/Release/quicsample -fsanitize=address -DSGFUZZ -lstdc++ -fsanitize=fuzzer -L/usr/lib/clang/17/lib/x86_64-unknown-linux-gnu -L/usr/bin/../lib/gcc/x86_64-linux-gnu/12 -L/usr/bin/../lib/gcc/x86_64-linux-gnu/12/../../../../lib64 -L/lib/x86_64-linux-gnu -L/lib/../lib64 -L/usr/lib/x86_64-linux-gnu -L/usr/lib/../lib64 -L/lib -L/usr/lib CMakeFiles/quicsample.dir/sample.c.o ../../../bin/Release/libmsquic.a ../../../obj/Release/libplatform.a ../../../_deps/opensslquic-build/openssl/lib/libssl.a ../../../_deps/opensslquic-build/openssl/lib/libcrypto.a -ldl /usr/lib/x86_64-linux-gnu/libatomic.so.1 /usr/lib/x86_64-linux-gnu/libnuma.so.1 -lpthread -lrt -lm -ldl -lresolv -lsFuzzer -lhfnetdriver -lhfcommon

    echo "done!"
}

function install_dependencies {
    sudo apt install -y libev-dev
}

function get_source {
    if [[ ! -d "src" ]]; then
        git clone https://github.com/ngtcp2/ngtcp2.git src || true
    fi
    cd src
    git checkout v1.4.0
    git submodule update --init --recursive --depth 1

    git clone https://github.com/ngtcp2/nghttp3
    cd nghttp3
    git checkout 7ca2b33423f4e706d540df780c7a1557affdc42c
    git submodule update --init

    cd ..
    git clone --depth 1 -b v5.7.0-stable https://github.com/wolfSSL/wolfssl
}
