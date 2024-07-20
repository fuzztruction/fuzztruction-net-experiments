#!/usr/bin/env bash

set -eu

# Build all binaries in this project without any additional instrumentation
function build_generator {
    mkdir -p inputs
    rm -rf generator/
    mkdir generator
    cd generator

    export FT_HOOK_INS=branch,store,select,switch
    export FT_CALL_INJECTION=1
    export CC=/home/user/fuzztruction/generator/pass/fuzztruction-source-clang-fast
    export CXX=/home/user/fuzztruction/generator/pass/fuzztruction-source-clang-fast++

    export CFLAGS="-DFT_FUZZING -DNDEBUG -DFT_GENERATOR"
    export CXXFLAGS="-DFT_FUZZING -DNDEBUG -DFT_GENERATOR"

    cmake ../src
    make -j
}

# Build all binaries in this project as a fuzz target
function build_consumer {
    rm -rf consumer
    mkdir consumer
    cd consumer

    export AFL_LLVM_LAF_SPLIT_SWITCHES=1
    export AFL_LLVM_LAF_TRANSFORM_COMPARES=1
    export AFL_LLVM_LAF_SPLIT_COMPARES=1

    export CC="afl-clang-fast"
    export CXX="afl-clang-fast++"
    export CFLAGS="-O3 -fsanitize=address -DFT_FUZZING -DFT_CONSUMER"
    export CXXFLAGS="-O3 -fsanitize=address -DFT_FUZZING -DFT_CONSUMER"
    export LDFLAGS="-fsanitize=address"

    cmake ../src
    make -j
}

function build_consumer_llvm_cov {
    rm -rf consumer_llvm_cov
    mkdir consumer_llvm_cov
    cd consumer_llvm_cov

    export AFL_LLVM_LAF_SPLIT_SWITCHES=1
    export AFL_LLVM_LAF_TRANSFORM_COMPARES=1
    export AFL_LLVM_LAF_SPLIT_COMPARES=1

    export CC=afl-clang-fast
    export CXX=afl-clang-fast++
    export CFLAGS="-O0 -DFT_FUZZING -DFT_CONSUMER -fsanitize=address -fprofile-instr-generate -fcoverage-mapping"
    export CXXFLAGS="-O0 -DFT_FUZZING -DFT_CONSUMER -fsanitize=address -fprofile-instr-generate -fcoverage-mapping"
    export LDFLAGS="-fsanitize=address -fprofile-instr-generate -fcoverage-mapping"
    export FT_IGNORE_TARGET_SIGTERM_HANDLER=1

    cmake ../src
    make -j
}

function build_consumer_afl_net {
    rm -rf consumer_afl_net
    mkdir -p consumer_afl_net
    cd consumer_afl_net

    export CC=/competitors/aflnet/afl-clang-fast
    export CXX=/competitors/aflnet/afl-clang-fast++
    export CFLAGS="-O3 -fsanitize=address -DFT_FUZZING -DFT_CONSUMER"
    export CXXFLAGS="-O3 -fsanitize=address -DFT_FUZZING -DFT_CONSUMER"
    export LDFLAGS="-fsanitize=address"

    cmake ../src
    make -j
}

function build_consumer_stateafl {
    rm -rf consumer_stateafl
    mkdir -p consumer_stateafl
    cd consumer_stateafl

    export ASAN_OPTIONS=detect_leaks=0
    export CC=/competitors/stateafl/afl-clang-fast
    export CXX=/competitors/stateafl/afl-clang-fast++
    export CFLAGS="-O3 -fsanitize=address -DFT_FUZZING -DFT_CONSUMER"
    export CXXFLAGS="-O3 -fsanitize=address -DFT_FUZZING -DFT_CONSUMER"
    export LDFLAGS="-fsanitize=address"

    cmake ../src
    make -j
}

function build_consumer_sgfuzz {
    rm -rf consumer_sgfuzz
    cp -r src consumer_sgfuzz
    cd consumer_sgfuzz

    export ASAN_OPTIONS=detect_leaks=0
    export CC=clang
    export CXX=clang++
    export CFLAGS="-O3 -fsanitize=fuzzer-no-link -fsanitize=address -DFT_FUZZING -DSGFUZZ -v -Wno-int-conversion"
    export CXXFLAGS="-O3 -fsanitize=fuzzer-no-link -fsanitize=address -DFT_FUZZING -DSGFUZZ -v -Wno-int-conversion"
    export LDFLAGS="-fsanitize=fuzzer-no-link -fsanitize=address"

    export FT_BLOCK_PATH_POSTFIXES="libsrc/ofchrenc.cc"
    python3 /competitors/SGFuzz/sanitizer/State_machine_instrument.py . -b <(echo "EC_Normal\nOFFilename\nnptr")

    mkdir build
    cd build
    cmake ../

    # This will failed because of the missing main method
    set +e
    make -j
    set -e

    cd dcmnet/apps
    clang -o ../../bin/dcmrecv -L/usr/lib/clang/17/lib/x86_64-unknown-linux-gnu -L/usr/bin/../lib/gcc/x86_64-linux-gnu/12 -L/usr/bin/../lib/gcc/x86_64-linux-gnu/12/../../../../lib64 -L/lib/x86_64-linux-gnu -L/lib/../lib64 -L/usr/lib/x86_64-linux-gnu -L/usr/lib/../lib64 -L/lib -L/usr/lib /usr/lib/clang/17/lib/x86_64-unknown-linux-gnu/libclang_rt.asan_static.a /usr/lib/clang/17/lib/x86_64-unknown-linux-gnu/libclang_rt.asan.a /usr/lib/clang/17/lib/x86_64-unknown-linux-gnu/libclang_rt.asan_cxx.a CMakeFiles/dcmrecv.dir/dcmrecv.cc.o ../../lib/libdcmnet.a ../../lib/libdcmdata.a ../../lib/liboflog.a ../../lib/libofstd.a ../../lib/libdcmtls.a ../../lib/libdcmnet.a ../../lib/libdcmdata.a ../../lib/liboflog.a /usr/lib/x86_64-linux-gnu/libz.so ../../lib/libofstd.a -lnsl ../../lib/liboficonv.a -lpthread -lrt /usr/lib/x86_64-linux-gnu/libssl.so /usr/lib/x86_64-linux-gnu/libcrypto.so -ldl -lstdc++ -lm -lpthread -lrt -lm -ldl -lresolv -lgcc_s -lgcc -lc -lgcc_s -lgcc -lsFuzzer -lhfnetdriver -lhfcommon -lstdc++ -fsanitize=fuzzer -fsanitize=address -DSGFUZZ

    echo "done"
}

function install_dependencies {
    true
}

function get_source {
    git clone http://git.dcmtk.org/dcmtk src
    cd src
    git checkout 1549d8ccccadad9ddd8a2bf75ff31eb554ee9dde
    git apply ../fuzzing.patch
    return 0
}
