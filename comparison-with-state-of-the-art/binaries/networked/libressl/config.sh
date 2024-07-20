#!/usr/bin/env bash

set -eu

function build_generator {
    rm -rf generator
    cp -r src generator

    pushd generator/libressl > /dev/null
    export FT_CALL_INJECTION=1
    export FT_HOOK_INS=call,branch,load,store,select,switch

    export CC=/home/user/fuzztruction/generator/pass/fuzztruction-source-clang-fast
    export CXX=/home/user/fuzztruction/generator/pass/fuzztruction-source-clang-fast++
    export CFLAGS="-g -O3 -DNDEBUG -D_FORTIFY_SOURCE=0 -DFT_FUZZING -DFT_GENERATOR"
    export CXXFLAGS="-g -O3 -DNDEBUG -D_FORTIFY_SOURCE=0 -DFT_FUZZING -DFT_GENERATOR"

    mkdir build
    cd build
    cmake ..
    bear -- make -j

    rm -rf ./libressl/build/tests
}

function build_consumer {
    rm -rf consumer
    cp -r src consumer

    pushd consumer/libressl > /dev/null
    export AFL_LLVM_LAF_SPLIT_SWITCHES=1
    export AFL_LLVM_LAF_TRANSFORM_COMPARES=1
    export AFL_LLVM_LAF_SPLIT_COMPARES=1

    export CC=afl-clang-fast
    export CXX=afl-clang-fast++
    export CFLAGS="-g -O3 -fsanitize=address -DFT_FUZZING -DFT_CONSUMER"
    export CXXFLAGS="-g -O3 -fsanitize=address -DFT_FUZZING -DFT_CONSUMER"

    mkdir build
    cd build
    cmake ..
    bear -- make -j

    rm -rf ./libressl/build/tests
}

function build_consumer_llvm_cov {
    rm -rf consumer_llvm_cov
    cp -r src consumer_llvm_cov/

    pushd consumer_llvm_cov/libressl > /dev/null

    export CC=afl-clang-fast
    export CXX=afl-clang-fast++
    export CFLAGS="-g -O0 -fsanitize=address -fprofile-instr-generate -fcoverage-mapping -DFT_FUZZING -DFT_CONSUMER"
    export CXXFLAGS="-g -O0 -fsanitize=address -fprofile-instr-generate -fcoverage-mapping -DFT_FUZZING -DFT_CONSUMER"
    export LDFLAGS="-fsanitize=address -fprofile-instr-generate -fcoverage-mapping"

    mkdir build
    cd build
    cmake ..
    bear -- make -j

    rm -rf ./libressl/build/tests
}

function build_consumer_afl_net {
    rm -rf consumer_afl_net
    cp -r src consumer_afl_net

    pushd consumer_afl_net/libressl > /dev/null

    export CC=/competitors/aflnet/afl-clang-fast
    export CXX=/competitors/aflnet/afl-clang-fast++
    export CFLAGS="-g -O3 -DFT_FUZZING -DFT_CONSUMER -fsanitize=address"
    export CXXFLAGS="-g -O3 -DFT_FUZZING -DFT_CONSUMER -fsanitize=address"

    mkdir build
    cd build
    cmake ..
    bear -- make -j

    rm -rf ./libressl/build/tests
}

function build_consumer_stateafl {
    rm -rf consumer_stateafl
    cp -r src consumer_stateafl

    pushd consumer_stateafl/libressl > /dev/null

    export CC=/competitors/stateafl/afl-clang-fast
    export CXX=/competitors/stateafl/afl-clang-fast++
    export CFLAGS="-g -O3 -DFT_FUZZING -DFT_CONSUMER -fsanitize=address"
    export CXXFLAGS="-g -O3 -DFT_FUZZING -DFT_CONSUMER -fsanitize=address"

    mkdir build
    cd build
    cmake ..
    bear -- make -j

    rm -rf ./libressl/build/tests
}

function build_consumer_sgfuzz {
    rm -rf consumer_sgfuzz
    cp -r src consumer_sgfuzz

    pushd consumer_sgfuzz/libressl > /dev/null

    export CC=clang
    export CXX=clang++
    export CFLAGS="-g -fsanitize=fuzzer-no-link -fsanitize=address -O3 -DFT_FUZZING -DFT_CONSUMER -DSGFUZZ -v -Wno-int-conversion"
    export CXXFLAGS="-g -fsanitize=fuzzer-no-link -fsanitize=address -O3 -DFT_FUZZING -DFT_CONSUMER -DSGFUZZ -v -Wno-int-conversion"

    python3 /competitors/SGFuzz/sanitizer/State_machine_instrument.py .

    mkdir build
    cd build
    cmake ..

    # Will fail because of missing main
    set +e
    bear -- make -j
    set -e

    cd apps/openssl
    clang -fsanitize=fuzzer -fsanitize=address -o openssl -L/usr/lib/clang/17/lib/x86_64-unknown-linux-gnu -L/usr/bin/../lib/gcc/x86_64-linux-gnu/12 -L/usr/bin/../lib/gcc/x86_64-linux-gnu/12/../../../../lib64 -L/lib/x86_64-linux-gnu -L/lib/../lib64 -L/usr/lib/x86_64-linux-gnu -L/usr/lib/../lib64 -L/lib -L/usr/lib /usr/lib/clang/17/lib/x86_64-unknown-linux-gnu/libclang_rt.asan_static.a /usr/lib/clang/17/lib/x86_64-unknown-linux-gnu/libclang_rt.asan.a  CMakeFiles/openssl.dir/apps.c.o CMakeFiles/openssl.dir/asn1pars.c.o CMakeFiles/openssl.dir/ca.c.o CMakeFiles/openssl.dir/ciphers.c.o CMakeFiles/openssl.dir/crl.c.o CMakeFiles/openssl.dir/crl2p7.c.o CMakeFiles/openssl.dir/cms.c.o CMakeFiles/openssl.dir/dgst.c.o CMakeFiles/openssl.dir/dh.c.o CMakeFiles/openssl.dir/dhparam.c.o CMakeFiles/openssl.dir/dsa.c.o CMakeFiles/openssl.dir/dsaparam.c.o CMakeFiles/openssl.dir/ec.c.o CMakeFiles/openssl.dir/ecparam.c.o CMakeFiles/openssl.dir/enc.c.o CMakeFiles/openssl.dir/errstr.c.o CMakeFiles/openssl.dir/gendh.c.o CMakeFiles/openssl.dir/gendsa.c.o CMakeFiles/openssl.dir/genpkey.c.o CMakeFiles/openssl.dir/genrsa.c.o CMakeFiles/openssl.dir/ocsp.c.o CMakeFiles/openssl.dir/openssl.c.o CMakeFiles/openssl.dir/passwd.c.o CMakeFiles/openssl.dir/pkcs12.c.o CMakeFiles/openssl.dir/pkcs7.c.o CMakeFiles/openssl.dir/pkcs8.c.o CMakeFiles/openssl.dir/pkey.c.o CMakeFiles/openssl.dir/pkeyparam.c.o CMakeFiles/openssl.dir/pkeyutl.c.o CMakeFiles/openssl.dir/prime.c.o CMakeFiles/openssl.dir/rand.c.o CMakeFiles/openssl.dir/req.c.o CMakeFiles/openssl.dir/rsa.c.o CMakeFiles/openssl.dir/rsautl.c.o CMakeFiles/openssl.dir/s_cb.c.o CMakeFiles/openssl.dir/s_client.c.o CMakeFiles/openssl.dir/s_server.c.o CMakeFiles/openssl.dir/s_socket.c.o CMakeFiles/openssl.dir/s_time.c.o CMakeFiles/openssl.dir/sess_id.c.o CMakeFiles/openssl.dir/smime.c.o CMakeFiles/openssl.dir/speed.c.o CMakeFiles/openssl.dir/spkac.c.o CMakeFiles/openssl.dir/ts.c.o CMakeFiles/openssl.dir/verify.c.o CMakeFiles/openssl.dir/version.c.o CMakeFiles/openssl.dir/x509.c.o CMakeFiles/openssl.dir/apps_posix.c.o CMakeFiles/openssl.dir/certhash.c.o ../../ssl/libssl.a ../../crypto/libcrypto.a -lpthread -lrt -lpthread -lrt -lm -ldl -lresolv -lgcc -lgcc_s -lc -lgcc -lsFuzzer -lhfnetdriver -lhfcommon -lstdc++
    rm -rf ./libressl/build/tests
    echo "done"

}


function install_dependencies {
    echo "No dependencies"
}

function get_source {
    mkdir -p src
    pushd src > /dev/null
    git clone https://github.com/libressl/portable.git libressl || true
    cd libressl
    git checkout v3.8.1
    git apply ../../fuzzing.patch
    ./autogen.sh
    popd > /dev/null
}
