from dataclasses import dataclass
import typing
from .target import FuzzerKind, Target, TargetSettings


@dataclass(unsafe_hash=True)
class Job:
    target: Target
    target_settings: TargetSettings
    repetition_ctr: int
    fuzzer: FuzzerKind

    def __init__(
        self,
        target: Target,
        target_settings: TargetSettings,
        repetition_ctr: int,
        fuzzer: FuzzerKind,
    ) -> None:
        self.target = target
        self.target_settings = target_settings
        self.repetition_ctr = repetition_ctr
        self.fuzzer = fuzzer

    def id(self, with_rep_ctr: bool = True) -> str:
        ret = f"{self.fuzzer.value}_{self.target.configuration_name}_{self.target_settings.cores_per_run}cores_{self.target_settings.timeout_in_s}s"
        if with_rep_ctr:
            ret += f"_{self.repetition_ctr+1}"
        return ret

    def runtime_s(self) -> int:
        return self.target_settings.timeout_in_s

    def configuration_and_cores_and_runtime_id(self) -> str:
        return f"target:{self.target.configuration_name},cores:{self.target_settings.cores_per_run},timeout:{self.target_settings.timeout_in_s}s"

    @staticmethod
    def from_target(target: Target, setting: TargetSettings) -> typing.List["Job"]:
        ret = []
        for rep_ctr in range(0, setting.repetitions):
            for fuzzer in setting.fuzzers_to_be_run:
                match fuzzer:
                    case (
                        FuzzerKind.AFLNET
                        | FuzzerKind.FT
                        | FuzzerKind.STATEAFL
                        | FuzzerKind.SGFUZZ
                    ):
                        ret.append(Job(target, setting, rep_ctr, fuzzer))
                    case other:
                        raise RuntimeError(f"The fuzzer {other} is not yet supported")
        return ret  # type: ignore

    @staticmethod
    def from_config(config) -> typing.List["Job"]:  # type: ignore
        ret = []
        for target_and_setting in config.targets:
            target = target_and_setting[0]
            settings = target_and_setting[1]
            ret += Job.from_target(target, settings)
        return ret
