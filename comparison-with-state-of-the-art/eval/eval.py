from pathlib import Path
import argparse
import os

from src.config import Config
from src.log import setup_main_logger
from src.manager import Manager

def get_image_name(args: argparse.Namespace) -> str:
    if args.use_prebuilt:
        return "fuzztruction-env-prebuilt"
    else:
        return "fuzztruction-env"

def setup_check_config_parser(parent_parser): # type: ignore
    check_config_parser: argparse.ArgumentParser = parent_parser.add_parser(
        "check-config", help="Check if the provided config is valid"
    )

    def check(args: argparse.Namespace):
        cfg_path = args.config_path
        config = Config.from_path(cfg_path)
        print("Config successfully loaded!")
        print(config)

    check_config_parser.set_defaults(func=check)


def setup_schedule_command(parent_parser): # type: ignore
    config_parser: argparse.ArgumentParser = parent_parser.add_parser(
        "schedule", help="Schedule jobs until all are done"
    )

    def schedule(args: argparse.Namespace):
        cfg_path = args.config_path
        config = Config.from_path(cfg_path)
        mgr = Manager(config, get_image_name(args))
        mgr.join()

    config_parser.set_defaults(func=schedule)


def setup_cleanup_command(parent_parser): # type: ignore
    config_parser: argparse.ArgumentParser = parent_parser.add_parser(
        "cleanup", help="Stop and remove all jobs that can not be found in the config"
    )

    def cleanup(args: argparse.Namespace):
        cfg_path = args.config_path
        config = Config.from_path(cfg_path)
        mgr = Manager(config, get_image_name(args), schedule=False)

    config_parser.set_defaults(func=cleanup)

def setup_stop_command(parent_parser): # type: ignore
    config_parser: argparse.ArgumentParser = parent_parser.add_parser(
        "stop", help="Stop and remove all running jobs."
    )

    def stop(args: argparse.Namespace):
        cfg_path = args.config_path
        config = Config.from_path(cfg_path)
        mgr = Manager(config, get_image_name(args), schedule=False)
        executors = mgr.executors()
        for e in executors:
            e.stop()

    config_parser.set_defaults(func=stop)

def main():
    log = setup_main_logger()

    cwd = Path(os.getcwd())
    expected_cwd = Path("~/fuzztruction-net/fuzztruction-experiments/comparison-with-state-of-the-art/eval").expanduser()
    if cwd != expected_cwd:
        log.error(f"Please make sure to clone the FuzztructionNet's main repository at the user's root directory, e.g., /home/<username>/fuzztruction-net.")
        log.error(f"Current working directory is {cwd} but expected {expected_cwd}.")
        exit(1)

    parser = argparse.ArgumentParser(
        prog="eval.py", description="Script for starting a fuzzer evaluation campaign for Fuzztruction-Net"
    )
    parser.add_argument("config_path", type=Path, help="Path to the eval config yaml file.")
    parser.add_argument("--use-prebuilt", action="store_true", default=False, required=False)


    subparsers = parser.add_subparsers(required=True, help="The operation to performe")
    setup_check_config_parser(subparsers)
    setup_cleanup_command(subparsers)
    setup_schedule_command(subparsers)
    setup_stop_command(subparsers)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
