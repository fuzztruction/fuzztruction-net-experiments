# Fuzztruction-Net Experiments

This repository contains all scripts and configurations needed to re-run the experiments conducted in our paper. This repository is embedded as a submodule in the context of [Fuzztruction-Net's main repository](https://github.com/fuzztruction/fuzztruction-net). Please read the whole documentation before conducting any experiment.

## Repository Layout
The folder `comparison-with-state-of-the-art` contains all data needed to rerun the evaluation.

### [binaries/networked](comparison-with-state-of-the-art/binaries/networked)
This folder contains scripts to build all binaries for all fuzzer configurations. Each subfolder has a file called `config.sh` that implements an interface to allow building a particular target. These interfaces can either be used by the `build.sh` or `build-all.sh` scripts in the [binaries](comparison-with-state-of-the-art/binaries/networked) folder.

> [!NOTE]
> The build scripts must be executed inside the Docker runtime environment described in the main repository. For ease of use, we recommand to use the pre-built runtime environment.

The scripts are called as follows:
```bash
# Execute the given *command* for the target located in *target-path*.
./build.sh <target-path> <command>

# Execute the given *command* for *all* targets in parallel.
./build-all.sh <command>
```

The following commands are currently supported:
| Mode  | Description  |
|---|---|
| `src`  | Download the source required to build the target.  |
| `deps` | Install the dependencies needed to execute the target. |
| `generator`   | Build the instrumented weird peer application needed for running Fuzztruction. |
| `consumer`  | Build the AFL++-instrumented target binary. |
| `consumer-llvm-cov`  | Build the target binary suitable for computing coverage using llvm coverage. |
| `consumer-afl-net`  | Build the target for fuzzing using AFLNet (if supported). |
| `consumer-stateafl`  | Build the target for fuzzing using StateAFL (if supported). |
| `consumer-sgfuzz`  | Build the target for fuzzing using SGFuzz (if supported). |

### [configurations/networked](comparison-with-state-of-the-art/configurations/networked)
This folder contains the configurations for all fuzzing targets evaluated in the paper. Each subfolder represents a target and contains the used seed files and a YAML configuration file defining how fuzzers should interface with it. These configuration files are passed via the command line to the `fuzztruction` binary as described in the [main repository](https://github.com/fuzztruction/fuzztruction-net).

Please look at `configurations/networked/dropbear/dbclient_dropbear.yml` for an extensively documented configuration file.

## Comparison with State of the Art
To reproduce the results presented in the paper, we describe how to setup and conduct the experiments to compare Fuzztruction-Net to state-of-the-art fuzzers.


### Target Preparation
Before the evaluation can be done, the target applications must be built. This can happen via the `build.sh` scripts introduced above, or by using the pre-built runtime environment as described in the [main repository](https://github.com/fuzztruction/fuzztruction-net).

> [!NOTE]
> Building all targets (e.g., via `build-all.sh all`) consumes a considerable amount of time. Thus, we strongly advise you to use our pre-built image.

### Resource Requirements
The evaluation in the paper was conducted on a system powered by two Intel(R) Xeon(R) Gold 5320 CPU @ 2.20GHz 26 cores each, equipped with 256GB of RAM.

Each of the targets was evaluated for 24 hours, 10 times each. This was done for each fuzzer configuration (FT-Net, AFLNet, SGFuzz, StateAFL). For each fuzzer configuration, 13 cores were assigned, such that we could run 4 experiments in parallel.

### Running the Experiments
> <b><span style="color:red">Note:</span></b> During evaluation, an instance of the Docker runtime environment is used for each specific target. This runtime environment must contain a compiled version of all targets that are referenced by the eval campaign configuration introduced below. Furthermore, please note that the `eval.py` script is intended to be used on the *host* and not inside a Docker container, such as Fuzztruction-Net's runtime environment.

The `eval` folder contains everything needed to run an automatically scheduled evaluation. The fuzzing campaign, including targets and fuzzers to consider, can be configured via the `campaign-config.yaml` file. Please have a look at the comments in `campaign-config.yaml` for details regarding the configuration. The config shipped as part of this repo does *not* use the exact settings of our paper evaluation, since the amount of computational ressource required is likely infeasible for most people reproducing our evaluation. Please check the config and verify it suits your goals and available computation resources. Also, we disable StateAFL by default, as it is quite buggy and requires frequent manual intervention. Our evaluation has shown that it does not contribute significantly better results, making it not worth the hassle. The only exception is mosquitto, but SGFuzz is even better.

After configuration, the host's Python environment for the evaluation script needs to be prepared by executing `prepare_env.sh`. After running the script, you should be instructed to enable the virtual environment by executing `source venv/bin/activate`.

Next, the evaluation can be started by executing `python3 eval.py campaign-config.yaml --use-prebuilt schedule` (the `--use-prebuilt` must be stripped if a locally build runtime should be used). During execution, logs are saved in a directory called `artifact-results/logs`. After a run terminated, the resulting artifacts are stored in `artifact-results/finished`. In case of encountering problems, please provide the logs alongside your report. Before conducting long runs, you should consider setting the `timeout` in the config to a relatively low value to test that everything is working smoothly.
> <b><span style="color:red">Note:</span></b> The script must be kept running for it to be able to schedule new fuzzing runs after previous runs terminated. Thus, it is recommended to run the script inside a `tmux` session. Alternatively, the script can be periodically manually executed after some runs have finished.

> <b><span style="color:red">Note:</span></b> Setting a timeout of, e.g, 24h, does not mean that all activity stops after exactly 24 hours, since coverage is computed afterwards automatically (this may take a couple of hours in some cases). Please keep this in mind when running the evaluation.


### Plotting
After all experiments started in the previous step have finished, i.e., the `eval.py` scrpit terminated, the results can be plotted. Plotting happens via the `plot.py` script located in the [eval](comparison-with-state-of-the-art/eval) folder. The script expects the results to be located in the `artifact-results` folder as configured in the `campaign-config.yaml` by default. If this path is changed, the script needs to be updated as well (by setting the line `ROOT = Path("artifact-results")` to the desired directory).

Same as for the `eval.py` script, the `plot.py` script depends on third party libraries and requires `prepare_env.sh` to be executed. Also, please remember to activate the environment via `source venv/bin/activate`. After the environment has been set-up, the plots can be generated by executing `python3 plot.py`. The plot are stored at `artifact-results/charts/` and come in different formats, such as `pdf`, `svg` and `png`.

In total, there should be eleven plots (i.e., files starting with a `target:` prefix). Nine of these plots should match the results visible in Figure 2 of our paper, while the `mosquitto_tls` and `live555_auth` plot should match Figure 3 and 4, respectively. Please note that fuzzing is an inherently stochastic process, which means that the results will not necessarily align exactly (all trends should be the same though). Also, depending on customized settings in `campaign-config.yaml` and the allocated resources, results might differ slightly.

In case (plots for) some targets are missing, please check `artifact-results/finished` and the logs located at `artifact-results/logs`. For rerunning an experiment, it is sufficient to delete the result artifacts of all runs by executing `rm -rf artifact-results/finished/ft_artifact_dbclient_dropbear_1_*`. Then, as described in the previous section, the deleted runs can be restarted by executing `python3 eval.py campaign-config.yaml schedule`.
