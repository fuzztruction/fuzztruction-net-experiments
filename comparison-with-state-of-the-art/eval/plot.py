# %%
import json
from typing import List, Tuple, no_type_check, Dict
import math
import datetime
import pickle
from pathlib import Path
from typing import Dict, List
from collections import defaultdict, deque
from pathlib import Path

import altair as alt
import pandas as pd
from dataclasses import dataclass

from src.target import FuzzerKind
from src.job import Job

import logging as log

alt.data_transformers.disable_max_rows()
alt.data_transformers.enable("vegafusion")


@dataclass
class CoveragePoint:
    ts_in_minute: int
    coverage: int


@dataclass(unsafe_hash=True)
class FuzzingRun:
    job: Job
    path: Path
    coverage_results_json: Path

    def __init__(self, job: Job, path: Path):
        self.job = job
        self.path = path
        self.coverage_results_json = self.path / "llvm-cov/results/coverage.json"
        if not self.coverage_results_json.exists():
            raise Exception(f"Failed to find {self.coverage_results_json}")
        if not json.loads(self.coverage_results_json.read_text()):
            raise Exception(f"File {self.coverage_results_json} is empty")

    def raw_coverage_data_sorted(self) -> List[Tuple[int, int]]:
        data = json.loads(self.coverage_results_json.read_text())
        data = sorted(data.items(), key=lambda e: int(e[0]))
        data = [(int(e[0]), int(e[1])) for e in data]
        return data

    def coverage_over_time_dict(self, max_minute: int = 24 * 60) -> Dict[int, int]:
        ret = {}
        coverage = self.coverage_over_time(max_minute=max_minute)
        for p in coverage:
            ret[p.ts_in_minute] = p.coverage
        return ret

    def coverage_over_time(self, max_minute: int = 60 * 24) -> List[CoveragePoint]:
        raw_data = self.raw_coverage_data_sorted()
        raw_data_queue = deque(raw_data)

        ret: List[CoveragePoint] = []
        last_value = 0
        for minute in range(0, max_minute):
            local_max = None
            while raw_data_queue:
                raw_point = raw_data_queue[0]
                ts_ms = raw_point[0]
                coverage = raw_point[1]
                if (ts_ms // 1000 // 60) < minute:
                    raw_data_queue.popleft()
                    local_max = coverage
                else:
                    break
            if local_max:
                last_value = local_max
            cov_point = CoveragePoint(minute, last_value)
            ret.append(cov_point)

        return ret


RUN_DURATION_IN_S = 3600 * 24
assert (RUN_DURATION_IN_S % 60) == 0
RUN_DURATION_IN_M = RUN_DURATION_IN_S // 60

FUZZER_COLOR = {
    "ft": "#d66368",
    "aflnet": "#f59c0c",
    "stateafl": "#109426",
    "sgfuzz": "#808b88",
}

ROOT = Path("artifact-results")
RESULT_DIR = ROOT / "finished"
CHARTS_DIR = ROOT / "charts"
CHARTS_SVG_DIR = CHARTS_DIR / "svg"
CHARTS_PNG_DIR = CHARTS_DIR / "png"
CHARTS_PDF_DIR = CHARTS_DIR / "pdf"

RUN_DIRS = sorted(list(RESULT_DIR.glob("*")))
FUZZING_RUNS: List[FuzzingRun] = []

MERGE_RUN_INTO = {"mosquitto-pub_mosquitto_1_fixed": "mosquitto-pub_mosquitto_1"}

for run_path in RUN_DIRS:
    info_dump = run_path / "run.pickle"
    if not info_dump.exists():
        log.warning(f"Skipping {run_path}, since it does not contain a run.pickle")
        continue
    job = pickle.load(info_dump.open("rb"))
    if merge_into := MERGE_RUN_INTO.get(job.target.configuration_name):
        job.target.configuration_name = merge_into
    try:
        run = FuzzingRun(job, run_path)
        FUZZING_RUNS.append(run)
    except Exception as e:
        log.error(f"Failed to parse run at {run_path}: {e}")

for run in FUZZING_RUNS:
    cov_over_time = run.coverage_over_time()
    value_1h = cov_over_time[60]
    last_value = cov_over_time[-1]
    if value_1h == last_value:
        log.warning(f"Values of run {run.job} seem odd")

end_coverage_stats_file = Path("coverage_stats.txt")
end_coverage_stats = []
for run in FUZZING_RUNS:
    cov = run.coverage_over_time_dict()
    cov_last_min = cov[60 * 24 - 1]
    end_coverage_stats += [
        f"{run.job.fuzzer.value},{run.job.target.configuration_name},{run.job.repetition_ctr},{run.job.runtime_s()}s,{cov_last_min}"
    ]
end_coverage_stats_file.write_text("\n".join(end_coverage_stats))


# %%


@no_type_check
def build_coverage_data_frame(run: FuzzingRun) -> pd.DataFrame:
    frame = defaultdict(list)
    max_minute = run.job.runtime_s() // 60

    coverage_over_time = run.coverage_over_time_dict()
    max_coverage = 0
    for minute in range(0, max_minute):
        frame["fuzzer"].append(run.job.fuzzer.value)
        frame["color"].append(FUZZER_COLOR[run.job.fuzzer.value])
        frame["target"].append(run.job.configuration_and_cores_and_runtime_id())
        frame["run_id"].append(run.job.repetition_ctr)
        frame["min"].append(minute)
        if coverage := coverage_over_time.get(minute):
            frame["y"].append(coverage)
            max_coverage = coverage
        else:
            frame["y"].append(max_coverage)

        frame["x"].append(datetime.datetime.utcfromtimestamp(minute * 60))

    return pd.DataFrame(frame)


FUZZING_RUN_TO_FRAME: Dict[FuzzingRun, pd.DataFrame] = dict()
for run in FUZZING_RUNS:
    frame = build_coverage_data_frame(run)
    FUZZING_RUN_TO_FRAME[run] = frame


def calculate_intervals(
    data: pd.DataFrame, interval_width: float = 0.66
) -> pd.DataFrame:
    y_vals_grouped_by_min = data.groupby("min")["y"].apply(list)
    interval_elm_cnt = math.floor(
        math.floor(len(y_vals_grouped_by_min[0]) * interval_width) / 2
    )
    interval_frame = defaultdict(list)
    index = []
    for min, y_vals in y_vals_grouped_by_min.items():
        elm_cnt = len(y_vals)
        if elm_cnt < 2:
            # Just copy the only value that is there.
            # (the resulting interval will have a width of 0)
            y_vals = y_vals * 2
        y_vals = sorted(y_vals)
        median_idx = elm_cnt // 2
        # print(interval_elm_cnt)
        # print(y_vals)
        lower_idx = median_idx - interval_elm_cnt
        if lower_idx < 0:
            lower_idx = 0
        lower_bound = y_vals[lower_idx]

        upper_idx = median_idx + interval_elm_cnt
        if upper_idx > len(y_vals) - 1:
            upper_idx = len(y_vals) - 1

        upper_bound = y_vals[upper_idx]
        assert lower_bound is not None
        assert upper_bound is not None
        index.append(min)
        interval_frame["min"].append(min)
        interval_frame["interval_lower"].append(lower_bound)
        interval_frame["interval_upper"].append(upper_bound)
    interval_frame = pd.DataFrame(interval_frame, index=index)
    return data.merge(interval_frame, on="min")


TARGET_TO_FUZZER_TO_FRAMES: Dict[str, Dict[FuzzerKind, List[pd.DataFrame]]] = (
    defaultdict(lambda: defaultdict(list))
)
for run, frame in FUZZING_RUN_TO_FRAME.items():
    TARGET_TO_FUZZER_TO_FRAMES[run.job.configuration_and_cores_and_runtime_id()][
        run.job.fuzzer
    ].append(frame)

TARGET_TO_FRAME: Dict[str, pd.DataFrame] = {}
for target, fuzzer_to_frames in TARGET_TO_FUZZER_TO_FRAMES.items():
    target_frames = []
    for fuzzer, frames in fuzzer_to_frames.items():
        merged_frames = calculate_intervals(pd.concat(frames))
        target_frames.append(merged_frames)
    TARGET_TO_FRAME[target] = pd.concat(target_frames)

# for target, frames in TARGET_TO_FRAMES.items():
#     TARGET_TO_FRAME[target] = pd.concat(frames)


CHARTS_DIR.mkdir(exist_ok=True)
CHARTS_SVG_DIR.mkdir(exist_ok=True)
CHARTS_PNG_DIR.mkdir(exist_ok=True)
CHARTS_PDF_DIR.mkdir(exist_ok=True)

# dict_keys(['gnutls_client_server_1', 'openssl_client_server_1', 'libressl_client_server_1', 'dbclient_dropbear_1', 'dcmsend_dcmrecv_1', 'mosquitto-pub_mosquitto_1', 'smbclient_smbd_1', 'siprtp_siprtp_1']
FUZZERS_TO_PLOT = ["gnutls_client_server_1", "openssl_client_server_1"]

# def compute_coverage_over_time(data: Dict[str, List[int]]) -> Dict[int, int]:
#     ts_to_num_covered_edges: Dict[int, int] = dict()


def set_style(chart: alt.Chart) -> alt.Chart:
    return (
        chart.configure(font="cmr10")
        .configure_axis(
            labelFontSize=18,
            titleFontSize=18,
        )
        .configure_title(
            fontSize=18,
        )
        .configure_legend(
            titleFontSize=20,
            labelFontSize=18,
            labelLimit=0,
        )
        .configure_view(
            continuousHeight=100,
            continuousWidth=100,
        )
    )


def generate_graph(target_name: str, frame: pd.DataFrame):
    print(f"Plotting {target_name}...")
    layers = []

    fuzzer_to_offset = {
        "ft": 0,
        "aflnet": 15,
        "stateafl": 30,
        "sgfuzz": 45,
    }

    max_interval_upper = frame["interval_upper"].max()
    y_scale = alt.Scale(domain=[0, max_interval_upper + int(0.05 * max_interval_upper)])

    color_custom_scale = alt.Scale(
        domain=list(FUZZER_COLOR.keys()), range=list(FUZZER_COLOR.values())
    )
    cov_line_chart = (
        alt.Chart(frame, title=target_name)
        .mark_line()
        .encode(
            x=alt.X("x:T", axis=alt.Axis(format="%H:%M"), title="Time [hh:mm]"),
            y=alt.Y("median(y)", title="#Covered Branches", scale=y_scale),
            # y=alt.Y("median(y)", title="#Covered Branches"),
            # shape=alt.Shape(f'fuzzer:N'),
            # color=alt.Color(f"fuzzer:N", title="Fuzzer"),
            color=alt.Color(f"fuzzer:N", title="Fuzzer", scale=color_custom_scale),
            # strokeDash="run_id",
        )
    ).properties(width=300, height=200)

    layers.append(cov_line_chart)

    dot_layer: alt.Chart = (
        alt.Chart(frame)
        .mark_point(filled=True, size=60)
        .encode(
            x=alt.X("x:T", axis=alt.Axis(format="%H:%M")),
            y=alt.Y("median(y)", scale=y_scale),
            shape=alt.Shape(
                f"fuzzer:N",
                legend=alt.Legend(orient="top"),
                scale=alt.Scale(domain=color_custom_scale.domain),
            ),
            color=alt.Color(
                f"fuzzer:N", legend=alt.Legend(orient="top"), scale=color_custom_scale
            ),
        )
        .transform_filter(alt.datum.fuzzer == "ft")
        .transform_filter(alt.datum.min % (240 + 0) == 0)
    )
    layers.append(dot_layer)

    dot_layer: alt.Chart = (
        alt.Chart(frame)
        .mark_point(filled=True, size=60)
        .encode(
            x=alt.X("x:T", axis=alt.Axis(format="%H:%M")),
            y=alt.Y("median(y)", scale=y_scale),
            shape=alt.Shape(
                f"fuzzer:N",
                legend=alt.Legend(orient="top"),
                scale=alt.Scale(domain=color_custom_scale.domain),
            ),
            color=alt.Color(
                f"fuzzer:N", legend=alt.Legend(orient="top"), scale=color_custom_scale
            ),
        )
        .transform_filter(alt.datum.fuzzer == "aflnet")
        .transform_filter(alt.datum.min % (240 + 60) == 0)
    )
    layers.append(dot_layer)

    dot_layer: alt.Chart = (
        alt.Chart(frame)
        .mark_point(filled=True, size=60)
        .encode(
            x=alt.X("x:T", axis=alt.Axis(format="%H:%M")),
            y=alt.Y("median(y)", scale=y_scale),
            shape=alt.Shape(
                f"fuzzer:N",
                legend=alt.Legend(orient="top"),
                scale=alt.Scale(domain=color_custom_scale.domain),
            ),
            color=alt.Color(
                f"fuzzer:N", legend=alt.Legend(orient="top"), scale=color_custom_scale
            ),
        )
        .transform_filter(alt.datum.fuzzer == "stateafl")
        .transform_filter(alt.datum.min % (240 + 120) == 0)
    )
    layers.append(dot_layer)

    dot_layer: alt.Chart = (
        alt.Chart(frame)
        .mark_point(filled=True, size=60)
        .encode(
            x=alt.X("x:T", axis=alt.Axis(format="%H:%M")),
            y=alt.Y("median(y)", scale=y_scale),
            shape=alt.Shape(
                f"fuzzer:N",
                legend=alt.Legend(orient="top"),
                scale=alt.Scale(domain=color_custom_scale.domain),
            ),
            color=alt.Color(
                f"fuzzer:N", legend=alt.Legend(orient="top"), scale=color_custom_scale
            ),
        )
        .transform_filter(alt.datum.fuzzer == "sgfuzz")
        .transform_filter(alt.datum.min % (240 + 180) == 0)
    )
    layers.append(dot_layer)

    interval_layer: alt.Chart = (
        alt.Chart(frame)
        .mark_area(opacity=0.2)
        .encode(
            color=alt.Color("fuzzer:N", legend=None, scale=color_custom_scale),
        )
        .transform_window(
            rollingy2="mean(interval_upper)",
            rollingy="mean(interval_lower)",
            frame=[-20, 0],
        )
        .encode(x=alt.X("x:T"), y=alt.Y("rollingy:Q"), y2="rollingy2")
    )
    layers.append(interval_layer)

    chart = alt.layer(
        *layers,
    )
    set_style(chart)
    return chart


def generate_diff_chart(target_name: str, frame: pd.DataFrame):
    print(f"Plotting {target_name}...")
    layers = []

    fuzzer_to_offset = {
        "ft": 0,
        "aflnet": 15,
        "stateafl": 30,
        "sgfuzz": 45,
    }

    max_interval_upper = frame["interval_upper"].max()
    y_scale = alt.Scale(domain=[0, max_interval_upper + int(0.05 * max_interval_upper)])

    color_custom_scale = alt.Scale(
        domain=list(FUZZER_COLOR.keys()), range=list(FUZZER_COLOR.values())
    )
    # format: [stroke len, space len]
    stroke_custom_scale = alt.Scale(domain=[True, False], range=[[1, 0], [4, 4]])

    cov_line_chart = (
        alt.Chart(frame, title=target_name)
        .mark_line()
        .encode(
            x=alt.X("x:T", axis=alt.Axis(format="%H:%M"), title="Time [hh:mm]"),
            y=alt.Y("median(y)", title="#Covered Branches", scale=y_scale),
            # y=alt.Y("median(y)", title="#Covered Branches"),
            # shape=alt.Shape(f'fuzzer:N'),
            # color=alt.Color(f"fuzzer:N", title="Fuzzer"),
            color=alt.Color(f"fuzzer:N", title="Fuzzer", scale=color_custom_scale),
            strokeDash=alt.StrokeDash(
                "auth:N", scale=stroke_custom_scale, legend=alt.Legend(orient="top")
            ),
        )
    ).properties(width=300, height=200)

    layers.append(cov_line_chart)

    dot_layer: alt.Chart = (
        alt.Chart(frame)
        .mark_point(filled=True, size=60)
        .encode(
            x=alt.X("x:T", axis=alt.Axis(format="%H:%M")),
            y=alt.Y("median(y)", scale=y_scale),
            shape=alt.Shape(
                f"fuzzer:N",
                legend=alt.Legend(orient="top"),
                scale=alt.Scale(domain=color_custom_scale.domain),
            ),
            color=alt.Color(
                f"fuzzer:N", legend=alt.Legend(orient="top"), scale=color_custom_scale
            ),
            strokeDash=alt.StrokeDash("auth:N", legend=None),
        )
        .transform_filter(alt.datum.fuzzer == "ft")
        .transform_filter(alt.datum.min % (240 + 0) == 0)
    )
    layers.append(dot_layer)

    dot_layer: alt.Chart = (
        alt.Chart(frame)
        .mark_point(filled=True, size=60)
        .encode(
            x=alt.X("x:T", axis=alt.Axis(format="%H:%M")),
            y=alt.Y("median(y)", scale=y_scale),
            shape=alt.Shape(
                f"fuzzer:N",
                legend=alt.Legend(orient="top"),
                scale=alt.Scale(domain=color_custom_scale.domain),
            ),
            color=alt.Color(
                f"fuzzer:N", legend=alt.Legend(orient="top"), scale=color_custom_scale
            ),
            strokeDash=alt.StrokeDash("auth:N", legend=None),
        )
        .transform_filter(alt.datum.fuzzer == "aflnet")
        .transform_filter(alt.datum.min % (240 + 60) == 0)
    )
    layers.append(dot_layer)

    dot_layer: alt.Chart = (
        alt.Chart(frame)
        .mark_point(filled=True, size=60)
        .encode(
            x=alt.X("x:T", axis=alt.Axis(format="%H:%M")),
            y=alt.Y("median(y)", scale=y_scale),
            shape=alt.Shape(
                f"fuzzer:N",
                legend=alt.Legend(orient="top"),
                scale=alt.Scale(domain=color_custom_scale.domain),
            ),
            color=alt.Color(
                f"fuzzer:N", legend=alt.Legend(orient="top"), scale=color_custom_scale
            ),
            strokeDash=alt.StrokeDash("auth:N", legend=None),
        )
        .transform_filter(alt.datum.fuzzer == "stateafl")
        .transform_filter(alt.datum.min % (240 + 120) == 0)
    )
    layers.append(dot_layer)

    dot_layer: alt.Chart = (
        alt.Chart(frame)
        .mark_point(filled=True, size=60)
        .encode(
            x=alt.X("x:T", axis=alt.Axis(format="%H:%M")),
            y=alt.Y("median(y)", scale=y_scale),
            shape=alt.Shape(
                f"fuzzer:N",
                legend=alt.Legend(orient="top"),
                scale=alt.Scale(domain=color_custom_scale.domain),
            ),
            color=alt.Color(
                f"fuzzer:N", legend=alt.Legend(orient="top"), scale=color_custom_scale
            ),
            strokeDash=alt.StrokeDash("auth:N", legend=None),
        )
        .transform_filter(alt.datum.fuzzer == "sgfuzz")
        .transform_filter(alt.datum.min % (240 + 180) == 0)
    )
    layers.append(dot_layer)

    # interval_layer: alt.Chart = (
    #     alt.Chart(frame)
    #     .mark_area(opacity=0.2)
    #     .encode(
    #         color=alt.Color("fuzzer:N", legend=None, scale=color_custom_scale),
    #         strokeDash=stroke_dash,
    #     )
    #     .transform_window(
    #         rollingy2="mean(interval_upper)",
    #         rollingy="mean(interval_lower)",
    #         frame=[-20, 0],
    #     )
    #     .encode(x=alt.X("x:T"), y=alt.Y("rollingy:Q"), y2="rollingy2")
    # )
    # layers.append(interval_layer)

    chart = alt.layer(
        *layers,
    )
    set_style(chart)
    return chart


def chart_matrix_layout(charts, row_len=4):
    row = alt.hconcat()
    rows = []
    for idx, chart in enumerate(charts):
        if idx > 0 and (idx) % row_len == 0:
            rows.append(row)
            row = alt.hconcat()
        row |= chart

    if row:
        rows.append(row)

    return alt.vconcat(*rows)


def save(name: str, chart):
    png_path = (CHARTS_PNG_DIR / name).with_suffix(".png")
    chart.save(png_path.as_posix(), scale_factor=3.0)
    pdf_path = (CHARTS_PDF_DIR / name).with_suffix(".pdf")
    chart.save(pdf_path)
    svg_path = (CHARTS_SVG_DIR / name).with_suffix(".svg")
    chart.save(svg_path)


def live555_auth():
    """
    The live555 auth case study plot.
    """
    without_auth = "target:live555_client_server_1,cores:13,timeout:86400s"
    with_auth = "target:live555_client_server_auth_1,cores:13,timeout:86400s"

    without_auth_df = TARGET_TO_FRAME[without_auth].copy()
    without_auth_df["auth"] = False

    with_auth_df = TARGET_TO_FRAME[with_auth].copy()
    with_auth_df["auth"] = True

    combined_df = pd.concat([without_auth_df, with_auth_df])
    chart = generate_diff_chart("live555_auth_with_diff_all", combined_df)
    save("live555_auth_with_diff_all", chart)

    without_auth_df = without_auth_df[without_auth_df.fuzzer != "aflnet"]
    without_auth_df = without_auth_df[without_auth_df.fuzzer != "stateafl"]
    with_auth_df = with_auth_df[with_auth_df.fuzzer != "aflnet"]
    with_auth_df = with_auth_df[with_auth_df.fuzzer != "stateafl"]
    combined_df = pd.concat([without_auth_df, with_auth_df])
    chart = generate_diff_chart("live555_auth_with_diff", combined_df)
    save("live555_auth_with_diff", chart)

    return chart


#live555_auth()

# %%


def mosquitto_tls():
    without_tls = "target:mosquitto-pub_mosquitto_1,cores:13,timeout:86400s"
    with_tls = "target:mosquitto-pub_mosquitto_1_tls,cores:13,timeout:86400s"

    without_auth_df = TARGET_TO_FRAME[without_tls].copy()
    without_auth_df["auth"] = False

    with_auth_df = TARGET_TO_FRAME[with_tls].copy()
    with_auth_df["auth"] = True

    combined_df = pd.concat([without_auth_df, with_auth_df])
    chart = generate_diff_chart("mosquitto_tls_with_diff_all", combined_df)
    save("mosquitto_tls_with_diff_all", chart)

    without_auth_df = without_auth_df[without_auth_df.fuzzer != "aflnet"]
    without_auth_df = without_auth_df[without_auth_df.fuzzer != "stateafl"]
    with_auth_df = with_auth_df[with_auth_df.fuzzer != "aflnet"]
    with_auth_df = with_auth_df[with_auth_df.fuzzer != "stateafl"]
    combined_df = pd.concat([without_auth_df, with_auth_df])
    chart = generate_diff_chart("mosquitto_tls_with_diff", combined_df)
    save("mosquitto_tls_with_diff", chart)

    return chart


#mosquitto_tls()

# %%


def plot_group_1(target_name_to_frame):
    print("Plotting group1")
    group_1 = [
        "target:dbclient_dropbear_1,cores:13,timeout:86400s",
        "target:dcmsend_dcmrecv_1,cores:13,timeout:86400s",
        "target:gnutls_client_server_1,cores:13,timeout:86400s",
        "target:libressl_client_server_1,cores:13,timeout:86400s",
        "target:mosquitto-pub_mosquitto_1,cores:13,timeout:86400s",
        "target:openssl_client_server_1,cores:13,timeout:86400s",
        "target:smbclient_smbd_1,cores:13,timeout:86400s",
        "target:live555_client_server_1,cores:13,timeout:86400s",
        "target:ngtcp2_client_nginx_server,cores:13,timeout:86400s",
    ]
    charts = []
    for target_name, frame in target_name_to_frame.items():
        if target_name in group_1:
            chart = generate_graph(target_name, frame)
            charts.append(chart)

    chart = chart_matrix_layout(charts, row_len=3)

    save("group_1", chart)


plot_group_1(TARGET_TO_FRAME)

# %%


def plot_all(target_name_to_frame):
    print("Plotting all")
    target_name_to_chart = {}

    for target_name, frame in target_name_to_frame.items():
        if "bugs_" in target_name:
            print(f"skipping {target_name=}")
            continue
        chart = generate_graph(target_name, frame)
        target_name_to_chart[target_name] = chart
        save(target_name, chart)

    all_charts = chart_matrix_layout(target_name_to_chart.values())
    save("all", all_charts)
    return target_name_to_chart


charts = plot_all(TARGET_TO_FRAME)

#with_auth = "target:live555_client_server_auth_1,cores:13,timeout:86400s"
#save("live555_auth", charts[with_auth])

print("Done!")
