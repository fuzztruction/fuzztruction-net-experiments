import threading
import time
from pathlib import Path
import typing as ty
import pickle

from src.config import Config
from src.job import Job
from src.log import (
    get_child_logger,
    get_thread_logger,
    set_as_thread_logger,
    set_job_log_path_resolver,
)
from src.remote import Executor

CONSECUTIVE_SPAWN_DELAY = 2
POLL_INTERVAL = 30

log = get_thread_logger()


class Manager:

    def __init__(self, config: Config, image_name: str, schedule: bool = True) -> None:
        self._config = config
        self._image_name = image_name
        self._remotes = self._config.remotes
        self._pending_jobs = sorted(
            Job.from_config(config), key=lambda e: e.repetition_ctr
        )

        self._done_or_running_jobs: ty.List[Job] = []
        log.info(f"The campaign has {len(self._pending_jobs)} jobs in total.")

        self._workdir = self._config.result_path
        self._workdir.mkdir(parents=True, exist_ok=True)
        log.info(f"Workdir for this campaign is {self._workdir}.")

        self._logs_dir = self._workdir / "logs"
        self._logs_dir.mkdir(exist_ok=True)

        debug_log_path = self._logs_dir / "manager-debug.log"
        warn_log_path = self._logs_dir / "manager-warn.log"

        self.log = get_child_logger(
            "manager", debug_log=debug_log_path, warn_log=warn_log_path
        )
        set_as_thread_logger(self.log)
        set_job_log_path_resolver(self.get_job_log_path)

        self._finished_runs_dir = self._workdir / "finished"
        self._finished_runs_dir.mkdir(exist_ok=True)

        self.mark_finished_jobs_as_done()
        self.connect_to_remotes()

        if not schedule:
            self._stopped = True
        else:
            self._stopped = False
            self._thread = threading.Thread(target=self._loop_wrapper)
            self._thread.start()

    def get_job_log_path(self, job: Job):
        return (self._logs_dir / job.id()).with_suffix(".txt")

    def get_job_result_path(self, job: Job) -> Path:
        return self._finished_runs_dir / job.id()

    def dump_job_info_to_disk(self, job: Job):
        info_path = self.get_job_result_path(job) / "run.pickle"
        pickle.dump(job, info_path.open("wb"))

    def mark_finished_jobs_as_done(self):
        log.info(f"Checking results directory for already finished jobs.")
        pending = self._pending_jobs.copy()
        for job in pending:
            if self.get_job_result_path(job).exists():
                self.dump_job_info_to_disk(job)
                self._done_or_running_jobs.append(job)
                self._pending_jobs.remove(job)
        self.log.info(
            f"{len(self._done_or_running_jobs)} of {len(self._done_or_running_jobs)+len(self._pending_jobs)} jobs done or running"
        )

    def on_job_finished(self, job: Job):
        if self.get_job_result_path(job).exists():
            self.dump_job_info_to_disk(job)

    def connect_to_remotes(self):
        for remote in self._remotes:
            jobs_left = remote.connect(
                self,
                self._pending_jobs,
                self.get_job_result_path,
                purge_unknown_jobs=True,
            )
            self._pending_jobs = jobs_left

    def stop(self):
        self._stopped

    def join(self):
        self._thread.join()

    def executors(self) -> ty.List[Executor]:
        ret = []
        for remote in self._remotes:
            ret.extend(remote.executors())
        return ret

    def are_all_jobs_done(self):
        if len(self._pending_jobs) == 0:
            log.info("All jobs scheduled")
            executors = self.executors()

            if not executors:
                log.info("All executors terminated, exiting...")
                return True
            else:
                log.info("There are still jobs running")
                return False

    def _loop_wrapper(self):
        try:
            set_as_thread_logger(self.log)
            self._loop()
        except KeyboardInterrupt:
            log.info("KeyboardInterrupt")
        except:
            log.error("Unexpected error", exc_info=True)

    def _loop(self):
        while not self._stopped:
            done = self.are_all_jobs_done()
            if done:
                break
            log.info(f"There are {len(self._pending_jobs)} pending jobs")

            for remote in self._remotes:
                available_coress = len(remote.get_free_cpus()) # type: ignore
                remote_allowed_tags = remote.tags()
                while True:
                    log.info(
                        f"Remote {remote.ssh_address()} has {available_coress} free cores"
                    )

                    job = self.get_schedulable_job(
                        available_coress, remote_allowed_tags
                    )
                    if job:
                        log.info(f"Going to schedule the following job: {job.id()}")

                        # Clear log from previously failed run (if any)
                        log_path = self.get_job_log_path(job)
                        log_path.unlink(missing_ok=True)

                        available_coress -= job.target_settings.cores_per_run
                        self._pending_jobs.remove(job)
                        self._done_or_running_jobs.append(job)
                        remote.spawn_executor(job, self.get_job_result_path, self._image_name)
                        time.sleep(CONSECUTIVE_SPAWN_DELAY)
                    else:
                        break

            time.sleep(POLL_INTERVAL)

    def get_schedulable_job(
        self, free_cores: int, remote_allowed_tags: ty.Set[str]
    ) -> ty.Optional[Job]:
        """
        Get a job that is pending and required `free_cores` at maximun.
        """
        if free_cores == 0:
            return None

        for job in self._pending_jobs:
            job_tags = set(job.target_settings.allowed_tags)
            log.info(f"job_tags={job_tags}")
            log.info(f"remote_Tags={remote_allowed_tags}")

            if (
                job.target_settings.cores_per_run <= free_cores
                and len(job_tags & remote_allowed_tags) > 0
            ):
                return job
        return None
