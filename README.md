# Fuzztruction Experiments

This repository contains scripts and configurations that allow re-running the experiments conducted in our paper. This repository is embedded as a submodule in the context of [Fuzztruction's main repository](https://github.com/fuzztruction/fuzztruction). Please read the whole documentation before conducting any experiment.
> <b><span style="color:red">Note:</span></b> This repository assumes that it is located at `/home/user/fuzztruction/fuzztruction-experiments` inside a Docker container instance of the Docker image described in the main repository linked above.

## Repository Layout
The folder `comparison-with-state-of-the-art` contains all data needed to rerun the evaluation.

### [binaries](comparison-with-state-of-the-art/binaries/)
This folder contains scripts to build all binaries for all fuzzer configurations. Each subfolder has a file called `config.sh` that implements an interface to allow building a particular target. These interfaces can either be used by the `build.sh` or `build-all.sh` scripts in the [binaries](comparison-with-state-of-the-art/binaries/) folder. The scripts are called as follows:
```bash
# Execute the given *command* for the target located in *target-path*.
./build.sh <target-path> <command>
# Execute the given *command* for all targets in parallel.
./build-all.sh <command>
```



The following commands are currently supported:
| Mode  | Description  |
|---|---|
| `src`  | Download the source required to build the target.  |
| `deps` | Install the dependencies needed to execute the target. |
| `ft`   | Build the instrumented source application needed for running Fuzztruction.  |
| `afl`  | Build the AFL++-instrumented target binary (consumer) used by Fuzztruction and AFL++. NOTE: This command requires a considerable amount of time (several hours) for some targets because of AFL++'s collision-free encoding, which can cause signfiicant compilation slowdown. Thus, we recommend using the pre-built version of Fuzztruction as described in the [main repository](https://github.com/fuzztruction/fuzztruction). |
| `symcc`  | Build the target binary instrumented with SymCC's compiler.  |
| `vanilla`  | Build the binary without any instrumentation. This is used for Weizz and coverage computation.  |
| `all`  | Run all commands mentioned above. |


### [configurations](comparison-with-state-of-the-art/configurations/)
This folder contains the configurations for all 12 fuzzing targets evaluated in the paper. Each subfolder represents a target and contains the used seed files and a YAML configuration file defining how fuzzers should interface with it. These configuration files are passed via the command line to the `fuzztruction` binary as described in the [main repository](https://github.com/fuzztruction/fuzztruction).

Please look at `pngtopng_pngtopng/pngtopng-pngtopng.yml` for an extensively documented configuration file.

## Comparison With State of the Art
To reproduce the results presented in the paper, we describe how to setup and conduct the experiments to compare Fuzztruction to state-of-the-art fuzzers.
> <b><span style="color:red">Note:</span></b> Building all targets (e.g., via `build-all.sh all`) consumes a considerable amount of time (several hours on our machine) because of AFL++'s collision free encoding. Thus, we strongly advise you to use our pre-built image.
### Resource Requirements
The evaluation in the paper was conducted on a system powered by two Intel(R) Xeon(R) Gold 5320 CPU @ 2.20GHz 26 cores each, equipped with 256GB of RAM. Furthermore, 600GB of swap space were used to keep the whole fuzzing corpus in RAM. While most targets perform well without the extra swap space, some target configurations, such as `readelf`, exceed the memory limit after several hours because of a large number of interesting inputs.

Each of the 12 targets was evaluated for 24 hours, 5 times each. This was done for each fuzzer configuration (AFL++, SYMCC, Fuzztruction w/o AFL++, and Fuzztruction w/ AFL++). For each fuzzer configuration, the 52 cores were assigned as follows:
  - AFL++:
    - AFL++ Master @ 1 core
    - AFL++ Slaves @ 51 cores
  - SYMCC
    - SYMCC Worker @ 26 cores
    - AFL++ Master @ 1 cores
    - AFL++ Slaves @ 25 cores
  - WEIZZ
    - WEIZZ Master @ 1 cores
    - WEIZZ Slave @ 51 cores
  - Fuzztruction w/o AFL++
    - Fuzztruction Worker @ 52 cores
  - Fuzztruction w/ AFL++
    - Fuzztruction Worker @ 26 cores
    - AFL++ Master @ 1 cores
    - AFL++ Slaves @ 25 cores

### Running the Experiments
The `scripts` folder contains everything needed to run an automatically scheduled evaluation. The fuzzing campaign, including targets and fuzzers to consider, can be configured via the `campaign.yml` file. We advise setting `cores-total` equal to `cores-per-target` for an exact reproduction of our results, since concurrently running different targets might affect each other's performance.

After configuration, the evaluation can be started by executing `python3 eval.py`. During execution, logs are saved in a directory called `logs`. In case of encountering problems, please provide the logs alongside your report. Before conducting long runs, you should consider setting the `timeout` to a relatively low value to test that everything is working smoothly.

During the execution of the script, the `fuzztruction` binary is consecutively called with the appropriate arguments to evaluate all enabled targets. The calls made are logged to `logs/main.log`, and each individual run is logged in a separate log file. Evaluation of one specific target/fuzzer combination happens as follows:
1. The `fuzztruction` binary is called using the appropriate arguments to start the fuzzing run. (Log suffix: `<Target-Specs>-<ID>-<fuzzer-name>.log`)
2. After termination, `fuzztruction tracer` is executed to produce coverage traces for all found fuzzing test cases (see main repository for details). (Log suffix: `<Target-Specs>-<ID>-tracing.log`)
3. After tracing, the traces are copied into the folder that can be configured via `results-path`.
 By default, it is set to `~/shared/eval-results`, a folder always mapped to the host machine, even if the pre-built image is used. Make sure that this directory is mapped to the host, such that data is not lost in case the container is deleted. (Log suffix: `<Target-Specs>-<ID>-syncing.log`)

> <b><span style="color:red">Note on data retention:</span></b> After traces have been copied to the output directory (Step 3), all other data produced by the run is deleted to make space for the next scheduled experiment. If this behavior is not desired, please adapt the corresponding `rsync` call in `eval.py` to persist additional data.


### Distributed Evaluation
Using different `campaign.yml` configurations allows running campaigns distributed on multiple systems. After termination, the results can be combined using `rsync` to merge all output directories on a single system. Make sure that the name of different runs does not collide by utilizing the `first_run_id` and `last_run_id` attributes. This is only necessary if multiple runs for the same target are conducted.
### Basic Block Coverage Computation and Plotting
Please consult the [Computing Coverage](https://github.com/fuzztruction/fuzztruction#computing-coverage) section for details regarding the coverage computation. In essence, the process boils down to calling `./target/debug/coverage` and passing the output directory as argument (e.g, `./target/debug/coverage ~/shared/eval-results`). Since -- depending on the target -- this process can take some time (around one hour on 52 cores), it is advisable to start it in a `tmux` session.

After coverage computation is finished, the graphs found in the paper can be plotted via the `plot.py` script located in the `plotting` subdirectory. While it expects five run for each target to draw the intervals (shaded areas), it also allows to plot fewer runs but emits a warning in this case.
