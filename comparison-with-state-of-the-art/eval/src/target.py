from enum import Enum
from dataclasses import dataclass
from pathlib import Path
import typing


class FuzzerKind(Enum):
    FT = "ft"
    AFLNET = "aflnet"
    AFLPP = "aflpp"
    SGFUZZ = "sgfuzz"
    STATEAFL = "stateafl"


class TargetName(Enum):
    DROP_BEAR = "dropbear"
    OPEN_SSL = "openssl"


@dataclass(unsafe_hash=True)
class TargetSettings:
    fuzzers_to_be_run: typing.Tuple[FuzzerKind]
    cores_per_run: int
    timeout_in_s: int
    repetitions: int
    allowed_tags: typing.Tuple[str]


@dataclass(unsafe_hash=True)
class DefaultTargetSettings:
    fuzzers_to_be_run: typing.Optional[typing.Tuple[FuzzerKind]] = None
    cores_per_run: typing.Optional[int] = None
    timeout_in_s: typing.Optional[int] = None
    repetitions: typing.Optional[int] = None
    allowed_tags: typing.Optional[typing.Tuple[str]] = None

    def update(self, update_from: "DefaultTargetSettings") -> "DefaultTargetSettings":
        if self.fuzzers_to_be_run is None:
            self.fuzzers_to_be_run = update_from.fuzzers_to_be_run
        if self.cores_per_run is None:
            self.cores_per_run = update_from.cores_per_run
        if self.timeout_in_s is None:
            self.timeout_in_s = update_from.timeout_in_s
        if self.repetitions is None:
            self.repetitions = update_from.repetitions
        if self.allowed_tags is None or not self.allowed_tags:
            self.allowed_tags = update_from.allowed_tags

        return self

    def into_target_settings(self) -> TargetSettings:
        assert self.fuzzers_to_be_run is not None
        assert self.cores_per_run is not None
        assert self.timeout_in_s is not None
        assert self.repetitions is not None
        assert self.allowed_tags is not None
        return TargetSettings(
            tuple(self.fuzzers_to_be_run),
            self.cores_per_run,
            self.timeout_in_s,
            self.repetitions,
            self.allowed_tags,
        )


@dataclass(unsafe_hash=True)
class Target:
    configuration_name: str
    # target_name: TargetName
    config: Path
    build_deps: typing.Tuple[str]
