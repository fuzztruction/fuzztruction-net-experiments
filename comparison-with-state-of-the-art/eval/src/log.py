import logging
import threading
from pathlib import Path
import typing as ty
from werkzeug.local import LocalProxy

# %(funcName)s()
DEFAULT_FORMATTER = logging.Formatter(
    "[%(asctime)s][%(name)s][%(levelname)s][%(filename)s:%(lineno)d]: %(message)s"
)
LOCALS = threading.local()

MAIN_LOGGER = logging.getLogger()


def setup_main_logger():
    logging.getLogger("urllib3.connectionpool").setLevel(logging.WARN)
    logging.getLogger("docker.auth").setLevel(logging.WARN)
    logging.getLogger("docker.utils.config").setLevel(logging.WARN)

    main_logger = MAIN_LOGGER
    main_logger.setLevel(logging.DEBUG)

    handler = logging.StreamHandler()
    handler.setFormatter(DEFAULT_FORMATTER)
    main_logger.addHandler(handler)

    set_as_thread_logger(main_logger)

    return main_logger


def get_child_logger(
    name: str,
    debug_log: ty.Optional[Path],
    warn_log: ty.Optional[Path],
    parent: logging.Logger = MAIN_LOGGER,
):
    child_logger = parent.getChild(name)

    if debug_log:
        file_handler = logging.FileHandler(debug_log)
        file_handler.setFormatter(DEFAULT_FORMATTER)
        file_handler.setLevel(logging.DEBUG)
        child_logger.addHandler(file_handler)

    if warn_log:
        file_handler = logging.FileHandler(warn_log)
        file_handler.setFormatter(DEFAULT_FORMATTER)
        file_handler.setLevel(logging.WARN)
        child_logger.addHandler(file_handler)

    return child_logger


def set_as_thread_logger(logger: logging.Logger):
    LOCALS.logger = logger


def get_thread_logger() -> logging.Logger:
    return LocalProxy(lambda: LOCALS.logger)


JOB_LOG_PATH_RESOLVER = None


def set_job_log_path_resolver(cb):
    global JOB_LOG_PATH_RESOLVER
    JOB_LOG_PATH_RESOLVER = cb


def get_job_logger(job, parent_logger) -> logging.Logger:
    child_logger = parent_logger.getChild(job.id())
    file_handler = logging.FileHandler(JOB_LOG_PATH_RESOLVER(job))
    file_handler.setFormatter(DEFAULT_FORMATTER)
    child_logger.addHandler(file_handler)
    return child_logger
