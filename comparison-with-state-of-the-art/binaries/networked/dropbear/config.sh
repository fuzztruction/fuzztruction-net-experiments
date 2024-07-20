#!/usr/bin/env bash

set -eu

function build_custom_generator {
    rm -rf custom_generator
    cp -r src custom_generator

    pushd custom_generator > /dev/null
    export FT_CALL_INJECTION=1
    export FT_HOOK_INS=call,branch,load,store,select,switch
    #export FT_HOOK_INS=call

    export CC=/home/user/fuzztruction/generator/pass/fuzztruction-source-clang-fast
    export CXX=/home/user/fuzztruction/generator/pass/fuzztruction-source-clang-fast++
    export CFLAGS="-g -O3 -DFT_FUZZING -DNDEBUG -DFT_GENERATOR -I/home/user/fuzztruction/generator/pass"
    export CXXFLAGS="-g -O3 -DFT_FUZZING -DNDEBUG -DFT_GENERATOR -I/home/user/fuzztruction/generator/pass"

    ./configure --disable-harden --enable-bundled-libtom
    bear -- make PROGRAMS="dropbear dbclient dropbearkey dropbearconvert scp" -j

    popd > /dev/null
}

function build_generator {
    rm -rf generator
    cp -r src generator

    pushd generator > /dev/null
    export FT_CALL_INJECTION=1
    export FT_HOOK_INS=call,branch,load,store,select,switch
    #export FT_HOOK_INS=call

    export CC=/home/user/fuzztruction/generator/pass/fuzztruction-source-clang-fast
    export CXX=/home/user/fuzztruction/generator/pass/fuzztruction-source-clang-fast++
    export CFLAGS="-g -O3 -DFT_FUZZING -DNDEBUG -DFT_GENERATOR -I/home/user/fuzztruction/generator/pass"
    export CXXFLAGS="-g -O3 -DFT_FUZZING -DNDEBUG -DFT_GENERATOR -I/home/user/fuzztruction/generator/pass"

    ./configure --disable-harden --enable-bundled-libtom
    bear -- make PROGRAMS="dropbear dbclient dropbearkey dropbearconvert scp" -j

    popd > /dev/null

    build_custom_generator
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
    export CFLAGS="-g -O3 -fsanitize=address -DFT_FUZZING -I/home/user/fuzztruction/generator/pass"
    export CXXFLAGS="-g -O3 -fsanitize=address -DFT_FUZZING -I/home/user/fuzztruction/generator/pass"
    export LDFLAGS="-fsanitize=address"

    ./configure
    bear -- make PROGRAMS="dropbear dbclient dropbearkey dropbearconvert scp" -j

    popd > /dev/null
}

function build_consumer_llvm_cov {
    rm -rf consumer_llvm_cov
    cp -r src consumer_llvm_cov

    pushd consumer_llvm_cov > /dev/null
    export AFL_LLVM_LAF_SPLIT_SWITCHES=1
    export AFL_LLVM_LAF_TRANSFORM_COMPARES=1
    export AFL_LLVM_LAF_SPLIT_COMPARES=1

    export CC=afl-clang-fast
    export CXX=afl-clang-fast++
    export CFLAGS="-g -O0 -DFT_FUZZING -fsanitize=address -fprofile-instr-generate -fcoverage-mapping -I/home/user/fuzztruction/generator/pass"
    export CXXFLAGS="-g -O0 -DFT_FUZZING -fsanitize=address -fprofile-instr-generate -fcoverage-mapping -I/home/user/fuzztruction/generator/pass"
    export LDFLAGS="-fsanitize=address -fprofile-instr-generate -fcoverage-mapping"

    ./configure
    bear -- make PROGRAMS="dropbear dbclient dropbearkey dropbearconvert scp" -j

    popd > /dev/null
}

function build_consumer_afl_net {
    rm -rf consumer_afl_net
    cp -r src consumer_afl_net

    pushd consumer_afl_net > /dev/null

    export CC=/competitors/aflnet/afl-clang-fast
    export CXX=/competitors/aflnet/afl-clang-fast++
    export CFLAGS="-g -O3 -fsanitize=address -DFT_FUZZING -I/home/user/fuzztruction/generator/pass"
    export CXXFLAGS="-g -O3 -fsanitize=address -DFT_FUZZING -I/home/user/fuzztruction/generator/pass"
    export LDFLAGS="-fsanitize=address"

    ./configure
    bear -- make PROGRAMS="dropbear dbclient dropbearkey dropbearconvert scp" -j

    popd > /dev/null
}

function build_consumer_stateafl {
    rm -rf consumer_stateafl
    cp -r src consumer_stateafl

    pushd consumer_stateafl > /dev/null

    export CC=/competitors/stateafl/afl-clang-fast
    export CXX=/competitors/stateafl/afl-clang-fast++
    export CFLAGS="-g -O3 -fsanitize=address -DFT_FUZZING -I/home/user/fuzztruction/generator/pass"
    export CXXFLAGS="-g -O3 -fsanitize=address -DFT_FUZZING -I/home/user/fuzztruction/generator/pass"
    export LDFLAGS="-fsanitize=address"

    ./configure
    bear -- make PROGRAMS="dropbear dbclient dropbearkey dropbearconvert scp" -j

    popd > /dev/null
}

function build_consumer_sgfuzz {
    rm -rf consumer_sgfuzz
    cp -r src consumer_sgfuzz

    pushd consumer_sgfuzz > /dev/null

    export CC=clang
    export CXX=clang++
    export CFLAGS="-g -O3 -fsanitize=fuzzer-no-link -fsanitize=address -DFT_FUZZING -DSGFUZZ -I/home/user/fuzztruction/generator/pass"
    export CXXFLAGS="-g -O3 -fsanitize=fuzzer-no-link -fsanitize=address -DFT_FUZZING -DSGFUZZ -I/home/user/fuzztruction/generator/pass"
    export LDFLAGS="-fsanitize=address"


    python3 /competitors/SGFuzz/sanitizer/State_machine_instrument.py . -b <(echo "type")

    ./configure

    # will fail because of missing main
    set +e
    make PROGRAMS="dropbear" -j
    set -e

    clang -Wl,-z,now -Wl,-z,relro -Wl,-pie -fsanitize=address -o dropbear -I/home/user/fuzztruction/generator/pass ./obj/dbutil.o ./obj/buffer.o ./obj/dbhelpers.o ./obj/dss.o ./obj/bignum.o ./obj/signkey.o ./obj/rsa.o ./obj/dbrandom.o ./obj/queue.o ./obj/atomicio.o ./obj/compat.o ./obj/fake-rfc2553.o ./obj/ltc_prng.o ./obj/ecc.o ./obj/ecdsa.o ./obj/sk-ecdsa.o ./obj/crypto_desc.o ./obj/curve25519.o ./obj/ed25519.o ./obj/sk-ed25519.o ./obj/dbmalloc.o ./obj/gensignkey.o ./obj/gendss.o ./obj/genrsa.o ./obj/gened25519.o ./obj/common-session.o ./obj/packet.o ./obj/common-algo.o ./obj/common-kex.o ./obj/common-channel.o ./obj/common-chansession.o ./obj/termcodes.o ./obj/loginrec.o ./obj/tcp-accept.o ./obj/listener.o ./obj/process-packet.o ./obj/dh_groups.o ./obj/common-runopts.o ./obj/circbuffer.o ./obj/list.o ./obj/netio.o ./obj/chachapoly.o ./obj/gcm.o ./obj/svr-kex.o ./obj/svr-auth.o ./obj/sshpty.o ./obj/svr-authpasswd.o ./obj/svr-authpubkey.o ./obj/svr-authpubkeyoptions.o ./obj/svr-session.o ./obj/svr-service.o ./obj/svr-chansession.o ./obj/svr-runopts.o ./obj/svr-agentfwd.o ./obj/svr-main.o ./obj/svr-x11fwd.o ./obj/svr-tcpfwd.o ./obj/svr-authpam.o libtomcrypt/libtomcrypt.a libtommath/libtommath.a -lz -lstdc++  -lcrypt -lsFuzzer -lhfnetdriver -lhfcommon
    echo "The undefined reference to main error is fine :=)"

    popd > /dev/null
}



function install_dependencies {
    echo "No dependencies"
}

function get_source {
    if [[ ! -d "src" ]]; then
        git clone https://github.com/mkj/dropbear.git src
    fi
    cd src
    git checkout 9925b005e5b71080535afc94955ef2fe8c9d4c77
    git apply ../fuzzing.patch
}
