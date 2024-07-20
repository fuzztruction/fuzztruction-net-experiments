#!/usr/bin/env bash

set -eu

function build_generator {
    mkdir -p inputs
    mkdir -p generator
    rm -rf generator
    cp -r src generator

    pushd generator/openssl > /dev/null
    export FT_CALL_INJECTION=1
    export FT_HOOK_INS=branch,load,store,select,switch
    ./config -d shared no-threads no-tests no-asm enable-asan no-cached-fetch no-async
    sed -i 's/CC=$(CROSS_COMPILE)gcc.*/CC=\/home\/user\/fuzztruction\/generator\/pass\/fuzztruction-source-clang-fast/g' Makefile
    sed -i 's/CXX=$(CROSS_COMPILE)g++.*/CXX=\/home\/user\/fuzztruction\/generator\/pass\/fuzztruction-source-clang-fast++/g' Makefile
    sed -i 's/CFLAGS=.*/CFLAGS=-O3 -g -DNDEBUG -DFUZZING_BUILD_MODE_UNSAFE_FOR_PRODUCTION -DFT_FUZZING -DFT_GENEARTOR/g' Makefile
    sed -i 's/CXXFLAGS=.*/CXXFLAGS=-O3 -DNDEBUG -g -DFUZZING_BUILD_MODE_UNSAFE_FOR_PRODUCTION -DFT_FUZZING -DFT_GENEARTOR/g' Makefile
    LDCMD=/home/user/fuzztruction/generator/pass/fuzztruction-source-clang-fast bear -- make -j

    rm -rf ./openssl/fuzz
    rm -rf ./openssl/test
    rm -rf ./openssl/.git

    popd > /dev/null
}

function build_consumer {
    mkdir -p consumer
    rm -rf consumer
    cp -r src consumer

    pushd consumer/openssl > /dev/null
    export AFL_LLVM_LAF_SPLIT_SWITCHES=1
    export AFL_LLVM_LAF_TRANSFORM_COMPARES=1
    export AFL_LLVM_LAF_SPLIT_COMPARES=1

    ./config -d shared no-threads no-tests no-asm enable-asan no-cached-fetch no-async
    sed -i 's/CC=$(CROSS_COMPILE)gcc.*/CC=afl-clang-fast/g' Makefile
    sed -i 's/CXX=$(CROSS_COMPILE)g++.*/CXX=afl-clang-fast++/g' Makefile
    sed -i 's/CFLAGS=.*/CFLAGS=-O3 -g -DFUZZING_BUILD_MODE_UNSAFE_FOR_PRODUCTION -DFT_FUZZING -DFT_CONSUMER -fsanitize=address/g' Makefile
    sed -i 's/CXXFLAGS=.*/CXXFLAGS=-O3 -g -DFUZZING_BUILD_MODE_UNSAFE_FOR_PRODUCTION -DFT_FUZZING -DFT_CONSUMER -fsanitize=address/g' Makefile
    bear -- make -j

    rm -rf ./openssl/fuzz
    rm -rf ./openssl/test
    rm -rf ./openssl/.git

    popd > /dev/null
}

function build_consumer_llvm_cov {
    mkdir -p consumer_llvm_cov
    rm -rf consumer_llvm_cov
    cp -r src consumer_llvm_cov

    pushd consumer_llvm_cov/openssl > /dev/null

    export AFL_LLVM_LAF_SPLIT_SWITCHES=1
    export AFL_LLVM_LAF_TRANSFORM_COMPARES=1
    export AFL_LLVM_LAF_SPLIT_COMPARES=1

    ./config -d -no-shared no-threads no-tests no-asm enable-asan no-cached-fetch no-async
    sed -i 's/CC=$(CROSS_COMPILE)gcc.*/CC=afl-clang-fast/g' Makefile
    sed -i 's/CXX=$(CROSS_COMPILE)g++.*/CXX=afl-clang-fast++/g' Makefile
    sed -i 's/CFLAGS=.*/CFLAGS=-O0 -g -DFUZZING_BUILD_MODE_UNSAFE_FOR_PRODUCTION -DFT_FUZZING -DFT_CONSUMER -fsanitize=address -fprofile-instr-generate -fcoverage-mapping/g' Makefile
    sed -i 's/CXXFLAGS=.*/CXXFLAGS=-O0 -g -DFUZZING_BUILD_MODE_UNSAFE_FOR_PRODUCTION -DFT_FUZZING -DFT_CONSUMER -fsanitize=address -fprofile-instr-generate -fcoverage-mapping/g' Makefile
    bear -- make -j

    rm -rf ./openssl/fuzz
    rm -rf ./openssl/test
    rm -rf ./openssl/.git

    popd > /dev/null
}

function build_consumer_afl_net {
    mkdir -p consumer_afl_net
    rm -rf consumer_afl_net
    cp -r src consumer_afl_net

    pushd consumer_afl_net/openssl > /dev/null

    ./config -d shared no-threads no-tests no-asm enable-asan no-cached-fetch no-async
    sed -i 's@CC=$(CROSS_COMPILE)gcc.*@CC=/competitors/aflnet/afl-clang-fast@g' Makefile
    sed -i 's@CXX=$(CROSS_COMPILE)g++.*@CXX=/competitors/aflnet/afl-clang-fast++@g' Makefile
    sed -i 's/CFLAGS=.*/CFLAGS=-O3 -g -DFUZZING_BUILD_MODE_UNSAFE_FOR_PRODUCTION -DFT_FUZZING -DFT_CONSUMER -fsanitize=address/g' Makefile
    sed -i 's/CXXFLAGS=.*/CXXFLAGS=-O3 -g -DFUZZING_BUILD_MODE_UNSAFE_FOR_PRODUCTION -DFT_FUZZING -DFT_CONSUMER -fsanitize=address/g' Makefile
    bear -- make -j

    rm -rf ./openssl/fuzz
    rm -rf ./openssl/test
    rm -rf ./openssl/.git

    popd > /dev/null
}

function build_consumer_stateafl {
    mkdir -p consumer_stateafl
    rm -rf consumer_stateafl
    cp -r src consumer_stateafl

    pushd consumer_stateafl/openssl > /dev/null

    ./config -d shared no-threads no-tests no-asm enable-asan no-cached-fetch no-async
    sed -i 's@CC=$(CROSS_COMPILE)gcc.*@CC=/competitors/stateafl/afl-clang-fast@g' Makefile
    sed -i 's@CXX=$(CROSS_COMPILE)g++.*@CXX=/competitors/stateafl/afl-clang-fast++@g' Makefile
    sed -i 's/CFLAGS=.*/CFLAGS=-O3 -g -DFUZZING_BUILD_MODE_UNSAFE_FOR_PRODUCTION -DFT_FUZZING -DFT_CONSUMER -fsanitize=address/g' Makefile
    sed -i 's/CXXFLAGS=.*/CXXFLAGS=-O3 -g -DFUZZING_BUILD_MODE_UNSAFE_FOR_PRODUCTION -DFT_FUZZING -DFT_CONSUMER -fsanitize=address/g' Makefile
    bear -- make -j

    rm -rf ./openssl/fuzz
    rm -rf ./openssl/test
    rm -rf ./openssl/.git

    popd > /dev/null
}

function build_consumer_sgfuzz {
    mkdir -p consumer_sgfuzz
    rm -rf consumer_sgfuzz
    cp -r src consumer_sgfuzz

    pushd consumer_sgfuzz/openssl > /dev/null

    python3 /competitors/SGFuzz/sanitizer/State_machine_instrument.py . # -b <(echo "type")

    ./config -d shared no-threads no-tests no-asm enable-asan no-cached-fetch no-async
    sed -i 's@CC=$(CROSS_COMPILE)gcc.*@CC=clang@g' Makefile
    sed -i 's@CXX=$(CROSS_COMPILE)g++.*@CXX=clang++@g' Makefile
    sed -i 's/CFLAGS=.*/CFLAGS=-O3 -g -DFUZZING_BUILD_MODE_UNSAFE_FOR_PRODUCTION -DFT_FUZZING -DFT_CONSUMER -DSGFUZZ -fsanitize=address -fsanitize=fuzzer-no-link -Wno-int-conversion/g' Makefile
    sed -i 's/CXXFLAGS=.*/CXXFLAGS=-O3 -g -DFUZZING_BUILD_MODE_UNSAFE_FOR_PRODUCTION -DFT_FUZZING -DFT_CONSUMER -DSGFUZZ -fsanitize=address -fsanitize=fuzzer-no-link -Wno-int-conversion/g' Makefile
    sed -i 's@-Wl,-z,defs@@g' Makefile

    set +e
    bear -- make -j
    set -e


    clang -O3 -g -DFUZZING_BUILD_MODE_UNSAFE_FOR_PRODUCTION -DFT_FUZZING -DFT_CONSUMER -DSGFUZZ -fsanitize=address -Wno-int-conversion -L.   \
        -o apps/openssl \
        apps/lib/openssl-bin-cmp_mock_srv.o \
        apps/openssl-bin-asn1parse.o apps/openssl-bin-ca.o \
        apps/openssl-bin-ciphers.o apps/openssl-bin-cmp.o \
        apps/openssl-bin-cms.o apps/openssl-bin-crl.o \
        apps/openssl-bin-crl2pkcs7.o apps/openssl-bin-dgst.o \
        apps/openssl-bin-dhparam.o apps/openssl-bin-dsa.o \
        apps/openssl-bin-dsaparam.o apps/openssl-bin-ec.o \
        apps/openssl-bin-ecparam.o apps/openssl-bin-enc.o \
        apps/openssl-bin-engine.o apps/openssl-bin-errstr.o \
        apps/openssl-bin-fipsinstall.o apps/openssl-bin-gendsa.o \
        apps/openssl-bin-genpkey.o apps/openssl-bin-genrsa.o \
        apps/openssl-bin-info.o apps/openssl-bin-kdf.o \
        apps/openssl-bin-list.o apps/openssl-bin-mac.o \
        apps/openssl-bin-nseq.o apps/openssl-bin-ocsp.o \
        apps/openssl-bin-openssl.o apps/openssl-bin-passwd.o \
        apps/openssl-bin-pkcs12.o apps/openssl-bin-pkcs7.o \
        apps/openssl-bin-pkcs8.o apps/openssl-bin-pkey.o \
        apps/openssl-bin-pkeyparam.o apps/openssl-bin-pkeyutl.o \
        apps/openssl-bin-prime.o apps/openssl-bin-progs.o \
        apps/openssl-bin-rand.o apps/openssl-bin-rehash.o \
        apps/openssl-bin-req.o apps/openssl-bin-rsa.o \
        apps/openssl-bin-rsautl.o apps/openssl-bin-s_client.o \
        apps/openssl-bin-s_server.o apps/openssl-bin-s_time.o \
        apps/openssl-bin-sess_id.o apps/openssl-bin-smime.o \
        apps/openssl-bin-speed.o apps/openssl-bin-spkac.o \
        apps/openssl-bin-srp.o apps/openssl-bin-storeutl.o \
        apps/openssl-bin-ts.o apps/openssl-bin-verify.o \
        apps/openssl-bin-version.o apps/openssl-bin-x509.o \
        apps/libapps.a -lssl -lcrypto -ldl -lsFuzzer -lhfnetdriver -lhfcommon -lstdc++ -fsanitize=fuzzer -fsanitize=address -DSGFUZZ


    echo "done!"

    rm -rf ./openssl/fuzz
    rm -rf ./openssl/test
    rm -rf ./openssl/.git

    popd > /dev/null
}

function install_dependencies {
    echo "No dependencies"
}

function get_source {
    mkdir -p src
    pushd src > /dev/null
    git clone git://git.openssl.org/openssl.git || true
    cd openssl
    git checkout openssl-3.1.3
    git apply ../../fuzzing.patch
    popd > /dev/null
}
