#!/usr/bin/env bash

set -eu

# Build all binaries in this project without any additional instrumentation
function build_generator {
    rm -rf generator/
    cp -r src generator
    cd generator

    export FT_CALL_INJECTION=1
    export FT_HOOK_INS=call,branch,load,store,select,switch
    export CC=/home/user/fuzztruction/generator/pass/fuzztruction-source-clang-fast
    export CXX=/home/user/fuzztruction/generator/pass/fuzztruction-source-clang-fast++

    export CFLAGS="-DNDEBUG -DFT_FUZZING -DFT_GENERATOR -g"
    export CXXFLAGS="-DNDEBUG -DFT_FUZZING -DFT_GENERATOR -g"

    mkdir build
    cd build
    cmake -DWITH_STATIC_LIBRARIES=ON ..
    bear -- make -j
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
    export CFLAGS="-g -O3 -fsanitize=address -DFT_FUZZING -DFT_CONSUMER"
    export CXXFLAGS="-g -O3 -fsanitize=address -DFT_FUZZING -DFT_CONSUMER"
    export LDFLAGS="-fsanitize=address"

    mkdir build
    cd build
    cmake -DWITH_STATIC_LIBRARIES=ON ..
    make -j
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
    export CFLAGS="-g -O0 -DFT_FUZZING -fsanitize=address -fprofile-instr-generate -fcoverage-mapping"
    export CXXFLAGS="-g -O0 -DFT_FUZZING -fsanitize=address -fprofile-instr-generate -fcoverage-mapping"
    export LDFLAGS="-fsanitize=address -fprofile-instr-generate -fcoverage-mapping"

    mkdir build
    cd build
    cmake -DWITH_STATIC_LIBRARIES=ON ..
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

    mkdir build
    cd build
    cmake -DWITH_STATIC_LIBRARIES=ON ..
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

    mkdir build
    cd build
    cmake -DWITH_STATIC_LIBRARIES=ON ..
    make -j

    popd > /dev/null
}


function build_consumer_sgfuzz {
    rm -rf consumer_sgfuzz
    cp -r src consumer_sgfuzz
    cd consumer_sgfuzz

    export CC=clang
    export CXX=clang++
    export CFLAGS="-g -O3 -fsanitize=address -fsanitize=fuzzer-no-link -DFT_FUZZING -DFT_CONSUMER -DSGFUZZ -v -Wno-int-conversion"
    export CXXFLAGS="-g -O3 -fsanitize=address -fsanitize=fuzzer-no-link -DFT_FUZZING -DFT_CONSUMER -DSGFUZZ -v -Wno-int-conversion"
    export LDFLAGS="-fsanitize=address -fsanitize=fuzzer-no-link"

    python3 /competitors/SGFuzz/sanitizer/State_machine_instrument.py . #  -b <(echo "EC_Normal\nOFFilename\nnptr")

    mkdir build
    cd build
    cmake -DWITH_STATIC_LIBRARIES=ON ..

    set +e
    make -j
    set -e

    cd src
    clang -o mosquitto -L/usr/lib/clang/17/lib/x86_64-unknown-linux-gnu -L/usr/bin/../lib/gcc/x86_64-linux-gnu/12 -L/usr/bin/../lib/gcc/x86_64-linux-gnu/12/../../../../lib64 -L/lib/x86_64-linux-gnu -L/lib/../lib64 -L/usr/lib/x86_64-linux-gnu -L/usr/lib/../lib64 -L/lib -L/usr/lib /usr/lib/clang/17/lib/x86_64-unknown-linux-gnu/libclang_rt.asan_static.a /usr/lib/clang/17/lib/x86_64-unknown-linux-gnu/libclang_rt.asan.a -dynamic-list=/home/user/fuzztruction/fuzztruction-experiments/comparison-with-state-of-the-art/binaries/networked/mosquitto/consumer_sgfuzz/src/linker.syms CMakeFiles/mosquitto.dir/__/lib/alias_mosq.c.o CMakeFiles/mosquitto.dir/bridge.c.o CMakeFiles/mosquitto.dir/bridge_topic.c.o CMakeFiles/mosquitto.dir/conf.c.o CMakeFiles/mosquitto.dir/conf_includedir.c.o CMakeFiles/mosquitto.dir/context.c.o CMakeFiles/mosquitto.dir/control.c.o CMakeFiles/mosquitto.dir/database.c.o CMakeFiles/mosquitto.dir/handle_auth.c.o CMakeFiles/mosquitto.dir/handle_connack.c.o CMakeFiles/mosquitto.dir/handle_connect.c.o CMakeFiles/mosquitto.dir/handle_disconnect.c.o CMakeFiles/mosquitto.dir/__/lib/handle_ping.c.o CMakeFiles/mosquitto.dir/__/lib/handle_pubackcomp.c.o CMakeFiles/mosquitto.dir/handle_publish.c.o CMakeFiles/mosquitto.dir/__/lib/handle_pubrec.c.o CMakeFiles/mosquitto.dir/__/lib/handle_pubrel.c.o CMakeFiles/mosquitto.dir/__/lib/handle_suback.c.o CMakeFiles/mosquitto.dir/handle_subscribe.c.o CMakeFiles/mosquitto.dir/__/lib/handle_unsuback.c.o CMakeFiles/mosquitto.dir/handle_unsubscribe.c.o CMakeFiles/mosquitto.dir/keepalive.c.o CMakeFiles/mosquitto.dir/logging.c.o CMakeFiles/mosquitto.dir/loop.c.o CMakeFiles/mosquitto.dir/__/lib/memory_mosq.c.o CMakeFiles/mosquitto.dir/memory_public.c.o CMakeFiles/mosquitto.dir/mosquitto.c.o CMakeFiles/mosquitto.dir/__/lib/misc_mosq.c.o CMakeFiles/mosquitto.dir/mux.c.o CMakeFiles/mosquitto.dir/mux_epoll.c.o CMakeFiles/mosquitto.dir/mux_poll.c.o CMakeFiles/mosquitto.dir/net.c.o CMakeFiles/mosquitto.dir/__/lib/net_mosq_ocsp.c.o CMakeFiles/mosquitto.dir/__/lib/net_mosq.c.o CMakeFiles/mosquitto.dir/__/lib/packet_datatypes.c.o CMakeFiles/mosquitto.dir/__/lib/packet_mosq.c.o CMakeFiles/mosquitto.dir/password_mosq.c.o CMakeFiles/mosquitto.dir/persist_read_v234.c.o CMakeFiles/mosquitto.dir/persist_read_v5.c.o CMakeFiles/mosquitto.dir/persist_read.c.o CMakeFiles/mosquitto.dir/persist_write_v5.c.o CMakeFiles/mosquitto.dir/persist_write.c.o CMakeFiles/mosquitto.dir/plugin.c.o CMakeFiles/mosquitto.dir/plugin_public.c.o CMakeFiles/mosquitto.dir/property_broker.c.o CMakeFiles/mosquitto.dir/__/lib/property_mosq.c.o CMakeFiles/mosquitto.dir/read_handle.c.o CMakeFiles/mosquitto.dir/retain.c.o CMakeFiles/mosquitto.dir/security.c.o CMakeFiles/mosquitto.dir/security_default.c.o CMakeFiles/mosquitto.dir/__/lib/send_mosq.c.o CMakeFiles/mosquitto.dir/send_auth.c.o CMakeFiles/mosquitto.dir/send_connack.c.o CMakeFiles/mosquitto.dir/__/lib/send_connect.c.o CMakeFiles/mosquitto.dir/__/lib/send_disconnect.c.o CMakeFiles/mosquitto.dir/__/lib/send_publish.c.o CMakeFiles/mosquitto.dir/send_suback.c.o CMakeFiles/mosquitto.dir/signals.c.o CMakeFiles/mosquitto.dir/__/lib/send_subscribe.c.o CMakeFiles/mosquitto.dir/send_unsuback.c.o CMakeFiles/mosquitto.dir/__/lib/send_unsubscribe.c.o CMakeFiles/mosquitto.dir/session_expiry.c.o CMakeFiles/mosquitto.dir/__/lib/strings_mosq.c.o CMakeFiles/mosquitto.dir/subs.c.o CMakeFiles/mosquitto.dir/sys_tree.c.o CMakeFiles/mosquitto.dir/__/lib/time_mosq.c.o CMakeFiles/mosquitto.dir/__/lib/tls_mosq.c.o CMakeFiles/mosquitto.dir/topic_tok.c.o CMakeFiles/mosquitto.dir/__/lib/util_mosq.c.o CMakeFiles/mosquitto.dir/__/lib/util_topic.c.o CMakeFiles/mosquitto.dir/__/lib/utf8_mosq.c.o CMakeFiles/mosquitto.dir/websockets.c.o CMakeFiles/mosquitto.dir/will_delay.c.o CMakeFiles/mosquitto.dir/__/lib/will_mosq.c.o -lssl -lcrypto -ldl -lm -lrt -lpthread -lrt -lm -ldl -lsFuzzer -lhfnetdriver -lhfcommon -lstdc++ -fsanitize=fuzzer -fsanitize=address -DSGFUZZ

    echo "done!"
}

function install_dependencies {
    sudo apt install -y xsltproc libcjson-dev docbook-xsl
}

function get_source {
    if [[ ! -d "src" ]]; then
        git clone https://github.com/eclipse/mosquitto.git src
    fi
    cd src
    git checkout v2.0.18
    git apply ../fuzzing.patch
}
