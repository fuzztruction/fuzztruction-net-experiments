from pathlib import Path
import typing
from typing import Any
import yaml
from collections import defaultdict
import re
import functools
from dataclasses import dataclass

from .remote import Remote
from .job import FuzzerKind
from .target import TargetSettings, DefaultTargetSettings, Target

UNSET = type("Unset")


def get_config_attribute(
    cfg: typing.Optional[typing.Dict[str, typing.Any]],
    attr_name: str,
    *,
    expected_type: type = UNSET,
    parser: typing.Optional[typing.Callable[[typing.Any], typing.Any]] = None,
    required: bool = True,
    default: typing.Any = None,
) -> typing.Any:
    if cfg is None and not required:
        return default
    assert cfg is not None

    key_exists = attr_name in cfg
    if not parser:
        parser = lambda e: e  # type: ignore

    if key_exists:
        val = cfg.get(attr_name)
        if expected_type is not UNSET and not isinstance(val, expected_type):
            raise TypeError(
                f'Expected type {expected_type} for argument "{attr_name}", but its of type {type(val)}.'
            )
        del cfg[attr_name]

        assert parser is not None
        return parser(val)
    else:
        if required:
            raise Exception(f'Missing required attrbiute "{attr_name}" ')
        return default


def parse_timeout_as_seconds(timeout: str) -> int:
    """
    Parse a timeout given as str, e.g., 60s, 12m, 4h, 1d as seconds.
    """
    match = re.match(r"([1-9][0-9]*)([smhd])", timeout)
    assert match
    assert len(match.groups()) == 2
    prefix = int(match.group(1))

    suffix = match.group(2)
    suffix_to_factor = {
        "s": 1,
        "m": 60,
        "h": 3600,
        "d": 3600 * 24,
    }

    factor = suffix_to_factor.get(suffix, None)
    if factor is None:
        raise ValueError(f"Unknown timeout suffix: {suffix}")

    seconds = prefix * factor
    return seconds


def parse_fuzzer_name(val: str) -> FuzzerKind:
    return FuzzerKind(val)


def parse_fuzzer_names(val: typing.List[str]) -> typing.Tuple[FuzzerKind]:
    ret = set()
    for e in val:
        ret.add(parse_fuzzer_name(e))
    return tuple(ret)


def parse_target_settings(
    val: typing.Optional[typing.Dict[str, typing.Any]]
) -> DefaultTargetSettings:
    fuzzers = get_config_attribute(
        val,
        "fuzzers",
        expected_type=list,
        parser=parse_fuzzer_names,
        required=False,
    )
    run_duration = get_config_attribute(
        val,
        "run-duration",
        parser=parse_timeout_as_seconds,
        required=False,
    )
    repetitions = get_config_attribute(
        val,
        "repetitions",
        expected_type=int,
        required=False,
    )
    cores_per_run = get_config_attribute(
        val,
        "cores-per-run",
        expected_type=int,
        required=False,
    )
    allowed_tags = tuple(
        get_config_attribute(
            val, "allowed-tags", expected_type=list, required=False, default=[]
        )
    )
    if val is not None and val.values():
        remaining_values = val.values()
        raise AttributeError(
            f"Unexpected attribute(s) in target settings: {remaining_values}"
        )

    return DefaultTargetSettings(
        fuzzers, cores_per_run, run_duration, repetitions, allowed_tags
    )


def parse_target(
    configuration_name: str,
    val: typing.Dict[str, typing.Any],
    default_settings: DefaultTargetSettings,
) -> typing.Tuple[Target, TargetSettings]:
    config_path = get_config_attribute(val, "config", parser=Path)

    build_deps = get_config_attribute(
        val,
        "build-target-dependencies",
        required=False,
        parser=tuple,
        default=(),
        expected_type=list,
    )
    settings = get_config_attribute(
        val,
        "target-settings",
        required=False,
        default=DefaultTargetSettings(),
        parser=parse_target_settings,
    )
    settings = settings.update(default_settings).into_target_settings()

    return Target(configuration_name, config_path, build_deps), settings


def parse_targets(
    val: typing.List[typing.Dict[str, typing.Dict[Any, Any]]],
    default_settings: typing.Optional[DefaultTargetSettings],
) -> list[typing.Tuple[Target, TargetSettings]]:
    if default_settings is None:
        default_settings = DefaultTargetSettings(None, None, None, None, None)

    targets = []
    configuration_name_cnt = defaultdict(int)
    for target in val:
        for configuration_name, target_attrs in target.items():
            configuration_name_cnt[configuration_name] += 1
            parsed_target = parse_target(
                configuration_name, target_attrs, default_settings
            )
            targets.append((parsed_target[0], parsed_target[1]))

    duplicates_found = False
    for target_name, cnt in configuration_name_cnt.items():
        if cnt > 1:
            duplicates_found = True
            print(f"[!] Duplicated configuration name: {target_name}")

    if duplicates_found:
        raise AttributeError("Duplicated configuration names found")

    return targets


def parse_remote(remote_name: str, attrs: typing.Dict[str, typing.Any]) -> Remote:
    ssh_address = get_config_attribute(attrs, "ssh-address", expected_type=str)
    cores = get_config_attribute(attrs, "cores", expected_type=int)
    tags = set(get_config_attribute(attrs, "tags", expected_type=list))
    return Remote(remote_name, ssh_address, cores, tags)


def parse_remotes(
    val: typing.List[typing.Dict[str, typing.Dict[str, typing.Any]]]
) -> typing.List[Remote]:
    remotes = []
    for remote in val:
        for remote_name, remote_attrs in remote.items():
            parsed_remote = parse_remote(remote_name, remote_attrs)
            remotes.append(parsed_remote)
    return remotes


@dataclass
class Config:
    result_path: Path
    default_target_settings: DefaultTargetSettings
    targets: typing.List[typing.Tuple[Target, TargetSettings]]
    remotes: typing.List[Remote]

    @staticmethod
    def from_path(config_path: Path) -> "Config":
        content = config_path.read_text()
        content = yaml.unsafe_load(content)
        assert isinstance(content, dict)

        result_path = get_config_attribute(
            content, "result-path", parser=Path, required=True
        )

        # Parse default settings
        default_target_settings = get_config_attribute(
            content,
            "default-target-settings",
            expected_type=dict,
            parser=parse_target_settings,
        )

        # Parse targets
        parse_targets_partial = functools.partial(
            parse_targets, default_settings=default_target_settings
        )
        targets = get_config_attribute(
            content, "targets", parser=parse_targets_partial, required=True
        )

        remotes = get_config_attribute(
            content, "remotes", parser=parse_remotes, required=True
        )

        # Parse remotes
        config = Config(result_path, default_target_settings, targets, remotes)
        return config
