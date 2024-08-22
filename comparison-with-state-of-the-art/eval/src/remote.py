from dataclasses import dataclass
import subprocess
import typing
import yaml
import requests
import time
import threading
from pathlib import Path
import docker
from .log import get_job_logger, get_thread_logger, set_as_thread_logger
from .target import FuzzerKind
from .job import Job

log = get_thread_logger()
EXECUTOR_POLL_INTERVAL = 30
STATS_UPDATE_INTERVAL = 120
EXECUTOR_RSYNC_INTERVAL = 600

RUN_SCRIPT_TEMPLATE = """
#!/bin/bash
echo "Executing run script..."
cd /home/user/fuzztruction
check_env.sh
sudo ldconfig

set -eu
cargo build

pushd fuzztruction-experiments/comparison-with-state-of-the-art/binaries/networked
deps=(@BUILD-DEPS@)
for target in ${deps[@]}; do
    ./build.sh $target deps
done
popd

@FUZZ-CMD@ || true

mkdir -p /home/user/fuzztruction/eval-result
sudo rm -rf /home/user/fuzztruction/eval-result/@JOB-ID@
sudo chown user -R @WORK-DIR@
rsync -a @WORK-DIR@/ /home/user/fuzztruction/eval-result/@JOB-ID@
@LLVM-CMD@
sudo chown user -R /home/user/fuzztruction/eval-result/@JOB-ID@
sudo chmod -R 777 /home/user/fuzztruction/eval-result
"""


def generate_run_script(job: Job) -> str:
    fuzzer = job.fuzzer
    match fuzzer:
        case FuzzerKind.FT:
            fuzzer_arg = "fuzz"
        case other:
            fuzzer_arg = other.value

    cores = job.target_settings.cores_per_run
    timeout_in_s = f"{job.target_settings.timeout_in_s}s"
    suffix = f"{job.id()}"
    target_config_path = job.target.config

    # Insider the container we are still fuzing ~/fuzztruction,
    parts = list(target_config_path.parts)
    assert parts[1] == "fuzztruction"
    parts[1] = "fuzztruction-net"
    local_target_config_path = Path(*parts)

    target_config_content = yaml.unsafe_load(
        local_target_config_path.expanduser().read_text()
    )
    workdir = target_config_content["work-directory"]
    workdir = f"{workdir}-{suffix}"

    build_deps = job.target.build_deps
    build_deps = " ".join(build_deps)

    template = RUN_SCRIPT_TEMPLATE
    fuzz_cmd = [
        "sudo",
        "./target/debug/fuzztruction",
        target_config_path.as_posix().replace("~", "/home/user/"),
        "--log-level",
        "debug",
        "--purge",
        "--no-log-output",
        "--suffix",
        suffix,
        fuzzer_arg,
        "-j",
        str(cores),
        "-t",
        str(timeout_in_s),
    ]
    # if fuzzer == FuzzerKind.FT:
    #     fuzz_cmd.append("--dynamic-job-spawning")

    joined_fuzz_cmd = " ".join(fuzz_cmd)
    template = template.replace("@FUZZ-CMD@", joined_fuzz_cmd)

    # files will be copied into the new workdir used below by the run script
    llvm_cmd = [
        "sudo",
        "./target/debug/fuzztruction",
        target_config_path.as_posix().replace("~", "/home/user/"),
        # "--suffix",
        # suffix,
        "--workdir",
        f"/home/user/fuzztruction/eval-result/{job.id()}",
        "llvm-cov",
        "-j",
        "5",
        "--with-post-processing",
        "-t 5s",
    ]
    joined_llvm_cmd = " ".join(llvm_cmd)
    template = template.replace("@LLVM-CMD@", joined_llvm_cmd)

    template = template.replace("@BUILD-DEPS@", build_deps)
    template = template.replace("@WORK-DIR@", workdir)
    template = template.replace("@JOB-ID@", job.id())

    template = template.lstrip()
    log.info(f"Run script:\n{template}")
    return template


class Executor:
    START_TS_LABEL = "start_ts"
    JOB_NAME_LABEL = "job_name"
    IS_FUZZTRUCTION_LABEL = "is_fuzztruction_container"

    def __init__(
        self,
        remote: "Remote",
        job: Job,
        result_path_resolver: typing.Callable[[Job], Path],
        cpu_binding_set: typing.List[int],
        image_name: str
    ) -> None:
        self._remote = remote
        self._job = job
        self._log = get_job_logger(job, log)
        self._should_stop = False
        self._start_ts: typing.Optional[int] = None
        self._container: typing.Optional[typing.Any] = None
        self._thread: typing.Optional[threading.Thread] = None
        self._result_path_resolver = result_path_resolver
        self._cpus = cpu_binding_set
        self._image_name: typing.Optional[str] = image_name

    @staticmethod
    def is_executor(container) -> typing.Optional[str]:
        # return Executor._get_label_value(container, Executor.IS_FUZZTRUCTION_LABEL) == "1"
        return Executor.get_job_id(container)

    @staticmethod
    def kill(container) -> None:
        container.remove(force=True)

    @staticmethod
    def try_from_container(
        remote: "Remote", container, assignable_jobs: typing.List[Job], result_path_resolver: typing.Callable[[Job], Path]  # type: ignore
    ) -> typing.Optional["Executor"]:
        start_ts = Executor.get_start_ts(container)
        job_id = Executor.get_job_id(container)
        if start_ts is None or job_id is None:
            # No container created by us
            return None

        job = [job for job in assignable_jobs if job.id() == job_id]
        if job:
            matching_job = job[0]
        else:
            log.warn(f"Failed to find matching job instance for {job_id}")
            return None

        executor = Executor(remote, matching_job, result_path_resolver, [], "EMPTY")
        executor._start_ts = start_ts
        executor._container = container
        executor._thread = threading.Thread(target=executor._loop_wrapper)
        executor._thread.start()
        return executor

    O = typing.TypeVar("O")

    @staticmethod
    def _get_label_value(
        container, key: str, parse_type: typing.Callable[[str], O] = str  # type: ignore
    ) -> typing.Optional[O]:
        """
        Get the value of the label `key` if it is set on `container`.
        """
        if val := container.labels.get(key):
            return parse_type(val)
        else:
            return None

    @staticmethod
    def get_start_ts(container) -> typing.Optional[int]:  # type: ignore
        return Executor._get_label_value(container, Executor.START_TS_LABEL, int)

    @staticmethod
    def get_job_id(container) -> typing.Optional[str]:  # type: ignore
        return Executor._get_label_value(container, Executor.JOB_NAME_LABEL)

    def cpuset(self) -> typing.Set[int]:
        result = set()
        # If the container terminated, it does not allocate any CPUs anymore.
        if self._container is None:
            return result
        cpuset_str: str = self._container.attrs["HostConfig"]["CpusetCpus"]

        for range_or_cpu in cpuset_str.split(","):
            match range_or_cpu.split("-"):
                case start, end:
                    cpu_ids = set(range(int(start), int(end) + 1))
                    result |= cpu_ids
                case cpu_id:
                    result.add(int(cpu_id[0]))
        return result

    def start(self):
        if self._thread is None:
            self._thread = self._spawn_thread()

    def job(self) -> Job:
        return self._job

    def id(self) -> str:
        return f"{self._remote.ssh_address()}-{self.job().id()}"

    def is_running(self) -> bool:
        assert self._thread
        return self._thread.is_alive()

    def join(self):
        assert self._thread
        self._thread.join()

    def stop(self):
        self._should_stop = True

    def _generate_labels(self) -> typing.Dict[str, str]:
        return {
            Executor.START_TS_LABEL: str(self._start_ts),
            Executor.JOB_NAME_LABEL: self._job.id(),
            Executor.IS_FUZZTRUCTION_LABEL: "1",
        }

    def _spawn_thread(self) -> threading.Thread:
        assert self._image_name is not None

        self._start_ts = int(time.time())
        dc = self._remote.docker_client()

        run_script = generate_run_script(self._job)
        environment = {
            "RUN_SCRIPT": run_script,
            "FT_NO_AFFINITY": "1",
        }

        labels = self._generate_labels()

        ulimits = [
            docker.types.Ulimit(name="msgqueue", hard=2097152000, soft=2097152000) # type: ignore
        ]

        volumes: typing.Dict[str, typing.Dict[str,str]] = {}
        if self._image_name == "fuzztruction-env":
            home_dir_path = self._remote.execute_on_remote(["echo $HOME"]).stdout.strip()
            fuzztruction_dir = Path(home_dir_path) / "fuzztruction-net"

            volumes = {
                f"{fuzztruction_dir.as_posix()}": {
                    "bind": "/home/user/fuzztruction",
                    "mode": "rw",
                },
            }
        else:
            # If this is a prebuilt image, all files should be part of the image itself, but we still need a way to
            # get the results out of the container.
            home_dir_path = self._remote.execute_on_remote(["echo $HOME"]).stdout.strip()
            fuzztruction_dir = Path(home_dir_path) / "fuzztruction-net" / "eval-result"
            volumes = {
                f"{fuzztruction_dir.as_posix()}": {
                    "bind": "/home/user/fuzztruction/eval-result",
                    "mode": "rw",
                },
            }

        log.info(f"volumes={volumes}")

        cpuset_cpus = None
        if self._cpus:
            cpuset_cpus = ",".join([str(i) for i in self._cpus])

        tmpfs = {"/tmp": "mode=777"}

        self._container = dc.containers.run(
            self._image_name,
            "bash -c 'set -eu; echo -e \"$RUN_SCRIPT\" | bash'",
            name=self.job().id(),
            detach=True,
            volumes=volumes, # type: ignore
            labels=labels,
            tmpfs=tmpfs,
            privileged=True,
            shm_size="128G",
            network_mode="host",
            environment=environment,
            ulimits=ulimits,
            cpuset_cpus=cpuset_cpus,
        )

        thread = threading.Thread(target=self._loop_wrapper)
        thread.start()
        return thread

    def _loop_wrapper(self):
        assert self._container
        set_as_thread_logger(self._log)
        retry = True

        while retry:
            retry = False
            try:
                self._loop()
            except requests.exceptions.ConnectionError:
                # Sometimes the connection to the docker daemon breaks. In that case, we retry connecting the container.
                log.warn(
                    f"Lost connection to docker container while executing job\njob: {self.job().id()}\nremote: {self._remote.ssh_address()}\ncontainer:{self._container.id}"
                )
                log.warn("Stacktrace", exc_info=True)
                log.warn("Trying to reconnect after 60 seconds")
                time.sleep(60)
                dc = self._remote.docker_client()
                container = dc.containers.get(self._container.id) # type: ignore
                self._container = container
                retry = True
                continue
            except:
                log.error(
                    f"Error while executing job\njob: {self.job().id()}\nremote: {self._remote.ssh_address()}\ncontainer:{self._container.id}"
                )
                log.error("Stacktrace", exc_info=True)

            self._remote.on_executor_termination(self)

    def _loop(self):
        assert self._container
        next_update_ts = int(time.time() + STATS_UPDATE_INTERVAL)
        # next_rsync_ts = int(time.time() + EXECUTOR_RSYNC_INTERVAL)
        log.info(f"container: {self._container.id}")
        log.info(f"host: {self._remote.ssh_address()}")

        # logs = self._container.logs(timestamps=True)
        # log.info("\n" + logs.decode())
        last_log_update = int(time.time())

        expected_duration = self._job.target_settings.timeout_in_s
        failed = False

        while not self._should_stop:
            time.sleep(EXECUTOR_POLL_INTERVAL)

            self._container.reload()
            status = self._container.status

            container_alive = status in ["created", "running"]
            if not container_alive:
                log.info("Wating for container exit status...")
                failed = self._container.wait()["StatusCode"] != 0
                if failed:
                    log.error("Container exits with an non zero exit code.")
                    log.error(
                        f"This is container {self._container.id} on {self._remote.ssh_address()}."
                    )
                    return #TODO: Remove

                log_info_or_error = (log.info, log.error)[failed]
                logs = self._container.logs(since=last_log_update, timestamps=True)
                log_info_or_error("\n" + logs.decode())
                log_info_or_error("Container terminated. Executor is terminating.")
                self._container.remove(force=True)
                self._container = None

                # sync results to local storage
                remote_path = Path("~/fuzztruction-net/eval-result") / self._job.id()
                self._remote.copy_from_remote(
                    remote_path,
                    self._result_path_resolver(self._job),
                    delete_source_files=True,
                )
                break

            # if self._job.target_settings.rsync_preiodically and time.time() > next_rsync_ts:
            #     next_rsync_ts = time.time() + EXECUTOR_RSYNC_INTERVAL
            #     remote_path
            #     self._remote.copy_from_remote()

            # poll the container log
            if time.time() > next_update_ts:
                log.info("Polling logs...")
                next_update_ts = int(time.time() + STATS_UPDATE_INTERVAL)
                logs = self._container.logs(
                    since=last_log_update, timestamps=True
                ).decode()
                if logs.strip() != "":
                    log.info("\n" + logs)
                last_log_update = int(time.time())

            # Check if the container should have already been terminated
            assert self._start_ts
            time_passed = time.time() - self._start_ts
            grace_period = expected_duration * 1
            if expected_duration < 3600:
                grace_period += 3600
            if time_passed > (expected_duration + grace_period):
                hours = time_passed / 3600
                log.warn(f"Job should have been terminated since {hours:.2f} hours. However, this might be just the coverage computation taking very long.")

        try:
            if self._container:
                self._container.stop()
        except:
            log.error("Failed to stop container", exc_info=True)


@dataclass
class Remote:
    _name: str
    _ssh_address: str
    _cores: int
    _tags: typing.Set[str]
    _docker_client: typing.Optional[docker.DockerClient] = None
    _manager = None  # type: ignore

    def docker_client(self):  # type: ignore
        if self._docker_client is None:
            self._docker_client = docker.DockerClient(
                f"ssh://{self._ssh_address}", use_ssh_client=True, timeout=60*30
            )
        return self._docker_client

    def ssh_address(self) -> str:
        return self._ssh_address

    def cores_total(self) -> int:
        return self._cores

    def copy_from_remote(
        self, remote: Path, local: Path, delete_source_files: bool = False
    ):
        delete_source_files_flag = ("", "--remove-source-files")[delete_source_files]
        cmd = f"rsync -a {delete_source_files_flag} {self._ssh_address}:{remote.as_posix()}/ {local.as_posix()}"
        log.info(f"Copying data from remote {self._ssh_address}: {cmd}")
        subprocess.run(cmd, shell=True, check=True)

    def execute_on_remote(
        self, shell_commands: typing.List[str]
    ) -> subprocess.CompletedProcess[typing.Any]:
        cmd = "\n".join(shell_commands).strip()
        log.info(f"Executing command on remote {self._ssh_address}:\n{cmd}")
        return subprocess.run(
            f"ssh {self._ssh_address} bash",
            input=cmd,
            shell=True,
            check=True,
            encoding="utf8",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )

    def executors(self) -> typing.List[Executor]:
        return self._executors

    def on_executor_termination(self, executor: Executor):
        self._executors.remove(executor)
        assert self._manager
        self._manager.on_job_finished(executor.job())

    def connect(
        self,
        manager,
        assignable_jobs: typing.List[Job],
        result_path_resolver: typing.Callable[[Job], Path],
        purge_unknown_jobs: bool = True,
    ) -> typing.List[Job]:
        log.info(f"Connection to host {self._ssh_address}")
        self._manager = manager
        try:
            subprocess.run(
                f"ssh {self._ssh_address} 'echo core | sudo tee /proc/sys/kernel/core_pattern'",
                stdin=None,
                shell=True,
                check=True,
            )
            subprocess.run(
                f"ssh {self._ssh_address} 'echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor'",
                stdin=None,
                shell=True,
                check=True,
            )
            subprocess.run(
                f"ssh {self._ssh_address} 'echo 0 | sudo tee /proc/sys/fs/suid_dumpable'",
                stdin=None,
                shell=True,
                check=True,
            )
            subprocess.run(
                f"ssh {self._ssh_address} 'echo 1 | sudo tee /proc/sys/kernel/perf_event_paranoid'",
                stdin=None,
                shell=True,
                check=True,
            )
            subprocess.run(
                f"ssh {self._ssh_address} 'sudo gpasswd -a $USER docker'",
                stdin=None,
                shell=True,
                check=True,
            )
            # Check if fuzztruction-net is checked out in the remotes home directory.
            subprocess.run(
                f"ssh {self._ssh_address} 'test -d ~/fuzztruction-net'",
                stdin=None,
                shell=True,
                check=True,
            )
            # Test if we can connect the  docker client
            _dc = self.docker_client()
            jobs_left = self._find_running_executors(
                assignable_jobs,
                result_path_resolver,
                purge_unknown_jobs=purge_unknown_jobs,
            )
        except Exception as e:
            raise Exception(f"Failed to connect to remote {self._name}") from e

        log.info("Connection test successful!")
        return jobs_left

    def spawn_executor(
        self, job: Job, result_path_resolver: typing.Callable[[Job], Path], image_name: str
    ) -> Executor:
        try:
            cpus_needed = job.target_settings.cores_per_run
            free_cpus = self.get_free_cpus(cpus_needed)
            assert free_cpus

            executor = Executor(
                self, job, result_path_resolver, cpu_binding_set=free_cpus, image_name=image_name
            )
            executor.start()
            self._executors.append(executor)
            return executor
        except Exception as e:
            raise Exception(f"on remote: {self._ssh_address}") from e

    def _find_running_executors(
        self,
        assignable_jobs: typing.List[Job],
        result_path_resolver: typing.Callable[[Job], Path],
        purge_unknown_jobs: bool,
    ) -> typing.List[Job]:
        self._executors = []

        for container in self.docker_client().containers.list(all=True):
            if Executor.get_job_id(container) is None:
                continue

            log.info(f"Trying to create executor form {container}")
            if executor := Executor.try_from_container(
                self, container, assignable_jobs, result_path_resolver
            ):
                assignable_jobs.remove(executor.job())
                self._executors.append(executor)
            elif job_id := Executor.is_executor(container):
                log.warn(f"Found job that is not part of this campaign: {job_id}")
                if purge_unknown_jobs:
                    log.warn(f"Killing unknown job {job_id}")
                    Executor.kill(container)

        log.info(f"Found {len(self._executors)} running executors.")
        return assignable_jobs

    def num_cpus(self) -> int:
        assert self._docker_client
        return self._docker_client.info()["NCPU"]

    def get_free_cpus(
        self, cpus_needed: typing.Optional[int] = None
    ) -> typing.Optional[typing.List[int]]:
        ncpu = min(self.num_cpus(), self._cores)
        cpu_set = set(range(0, ncpu))
        executors = self.executors()

        for executor in executors:
            used_cpus = executor.cpuset()
            cpu_set -= used_cpus

        cpu_set = sorted(list(cpu_set))
        if cpus_needed is not None:
            if cpus_needed > len(cpu_set):
                return None
            cpu_set = cpu_set[:cpus_needed]

        return cpu_set

    def tags(self) -> typing.Set[str]:
        return set(self._tags)

    def stop_executors(self):
        for executor in self._executors:
            assert isinstance(executor, Executor)
            executor.stop()
        for executor in self._executors:
            assert isinstance(executor, Executor)
            executor.join()