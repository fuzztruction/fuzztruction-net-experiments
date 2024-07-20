#!/usr/bin/env bash

set -eu

function build_generator {
    mkdir -p inputs
    mkdir -p generator
    rm -rf generator
    cp -r src generator

    pushd generator > /dev/null
    export FT_CALL_INJECTION=1
    export FT_HOOK_INS=call,branch,load,store,select,switch

    export CC=/home/user/fuzztruction/generator/pass/fuzztruction-source-clang-fast
    export CXX=/home/user/fuzztruction/generator/pass/fuzztruction-source-clang-fast++
    export CFLAGS="-g -O3 -DNDEBUG -DFT_FUZZING -DFT_CONSUMER"
    export CXXFLAGS="-g -O3 -DNDEBUG -DFT_FUZZING -DFT_CONSUMER"

    sed -i "s@^C_COMPILER.*@C_COMPILER = $CC@g" config.linux
    sed -i "s@^CPLUSPLUS_COMPILER.*@CPLUSPLUS_COMPILER = $CXX@g" config.linux
    sed -i "s@^LINK =.*@LINK = $CXX -o@g" config.linux
    ./genMakefiles linux
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
    export CFLAGS="-g -fsanitize=address -O3 -DFT_FUZZING -DFT_CONSUMER"
    export CXXFLAGS="-g -fsanitize=address -O3 -DFT_FUZZING -DFT_CONSUMER"
    export LDFLAGS="-fsanitize=address"

    sed -i "s@^C_COMPILER.*@C_COMPILER = $CC@g" config.linux
    sed -i "s@^CPLUSPLUS_COMPILER.*@CPLUSPLUS_COMPILER = $CXX@g" config.linux
    sed -i "s@^LINK =.*@LINK = $CXX -o@g" config.linux
    ./genMakefiles linux
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
    export CFLAGS="-g -O0 -fsanitize=address -DFT_FUZZING -DFT_CONSUMER -fprofile-instr-generate -fcoverage-mapping"
    export CXXFLAGS="-g -O0  -fsanitize=address -DFT_FUZZING -DFT_CONSUMER -fprofile-instr-generate -fcoverage-mapping"
    export LDFLAGS="-fsanitize=address -fprofile-instr-generate -fcoverage-mapping"

    sed -i "s@^C_COMPILER.*@C_COMPILER = $CC@g" config.linux
    sed -i "s@^CPLUSPLUS_COMPILER.*@CPLUSPLUS_COMPILER = $CXX@g" config.linux
    sed -i "s@^LINK =.*@LINK = $CXX -o@g" config.linux
    ./genMakefiles linux
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

    sed -i "s@^C_COMPILER.*@C_COMPILER = $CC@g" config.linux
    sed -i "s@^CPLUSPLUS_COMPILER.*@CPLUSPLUS_COMPILER = $CXX@g" config.linux
    sed -i "s@^LINK =.*@LINK = $CXX -o@g" config.linux
    ./genMakefiles linux
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

    sed -i "s@^C_COMPILER.*@C_COMPILER = $CC@g" config.linux
    sed -i "s@^CPLUSPLUS_COMPILER.*@CPLUSPLUS_COMPILER = $CXX@g" config.linux
    sed -i "s@^LINK =.*@LINK = $CXX -o@g" config.linux
    ./genMakefiles linux
    make -j
}


function build_consumer_sgfuzz {
    rm -rf consumer_sgfuzz
    cp -r src-sgfuzz consumer_sgfuzz
    cd consumer_sgfuzz

    export CC=clang
    export CXX=clang++
    export CFLAGS="-g -O3 -fsanitize=address -fsanitize=fuzzer-no-link -DSGFUZZ -v -Wno-int-conversion"
    export CXXFLAGS="-g -O3 -fsanitize=address -fsanitize=fuzzer-no-link -DSGFUZZ -v -Wno-int-conversion"
    export LDFLAGS="-fsanitize=address -fsanitize=fuzzer-no-link"

    python3 /competitors/SGFuzz/sanitizer/State_machine_instrument.py . #  -b <(echo "EC_Normal\nOFFilename\nnptr")

    sed -i "s@^C_COMPILER.*@C_COMPILER = $CC@g" config.linux
    sed -i "s@^CPLUSPLUS_COMPILER.*@CPLUSPLUS_COMPILER = $CXX@g" config.linux
    sed -i "s@^LINK =.*@LINK = $CXX -o@g" config.linux

    set +e
    ./genMakefiles linux
    make -j
    set -e

    cd testProgs
    clang++ -otestOnDemandRTSPServer -L. -fsanitize=address -DFT_FUZZING -DSGFUZZ -DFT_CONSUMER testOnDemandRTSPServer.o announceURL.o ../liveMedia/libliveMedia.a ../groupsock/libgroupsock.a ../BasicUsageEnvironment/libBasicUsageEnvironment.a ../UsageEnvironment/libUsageEnvironment.a -lssl -lcrypto -lsFuzzer -lhfnetdriver -lhfcommon -lstdc++ -fsanitize=fuzzer -fsanitize=address -DSGFUZZ

    echo "done!"
}

function install_dependencies {
    echo "No dependencies"
}

function get_source {
    if [[ ! -d "src" ]]; then
        git clone https://github.com/rgaufman/live555.git src || true
    fi
    cp -r src src-sgfuzz
    cd src
    git checkout 2c92a57ca04b83b2038ab2ab701d05a54be06a85
    git apply ../fuzzing.patch
    # just a unpatched version (except const session id), since our patch to `src` is quit involved
    cd src-sgfuzz
    git checkout 2c92a57ca04b83b2038ab2ab701d05a54be06a85
    git apply ../sgfuzz-fuzzing.patch
}
