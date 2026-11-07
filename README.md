# BrainVision preprocessing with EEGLAB

This is a configurable MATLAB workflow that calls EEGLAB plugins. It does not
install a new EEGLAB menu. Keep the repository outside `eeglab/plugins` and add
its root to the MATLAB path.

## Setup

Tested with MATLAB R2023b and EEGLAB 2024.2. Install these plugins through
EEGLAB's extension manager: bva-io, firfilt, clean_rawdata, ICLabel and DIPFIT
(the default standard electrode montage comes from DIPFIT). Signal Processing
Toolbox is required by the preprocessing functions. Initialize EEGLAB first.

```matlab
addpath('/path/to/eeglab'); eeglab('nogui');
addpath('/path/to/eeg_preprocess_BrainVision');
config = struct;
config.RAW_DIR = '/path/to/brainvision/files';
config.CLEAN_DIR = '/path/to/new/cleaned/results';
config.QC_EVENTS = {'S  1','S  2'}; % exact markers from your recordings
config.REF_LABEL = 'FCz';         % the omitted recording reference, if any
config.seed = 42;
run_brainvision_preprocessing(config);
```

`preprocess_template.m` is an editable example for the same function.
BrainVision headers, markers and binary data must remain together. Nested
input folders are searched; file basenames must be unique. Existing output
files with the same names will be replaced, so use a new output directory for
comparisons.

## Study-specific settings

Set `SEL_CHANS` for your cap (default: 31 selected electrodes). `REF_LABEL`
reconstructs a zero-valued omitted acquisition reference before average
referencing. Use `''` when no omitted reference should be added; this setting
must match the recording setup. Set `CHANNEL_LOC_FILE` for a custom montage.

The processing order is load, select/reference, resample/filter, ASR sweep,
interpolation/reference, ICA, ICLabel threshold search, save and QC logs.
Optional configuration fields include:

| Field | Default |
|---|---|
| `TARGET_SRATE` | 500 Hz |
| `HP_CUTOFF_HZ`, `LP_CUTOFF_HZ` | 1, 30 Hz; `[]` skips that filter |
| `QC_BASE_MS`, `QC_WINDOW_MS` | [-200 0], [10 600] |
| `QC_INNER_CHANNEL` | cap-dependent inner electrodes |
| `flatlineVals` | [3 5 8] seconds |
| `chanCorrVals` | [0.60 0.70 0.80 0.90] |
| `burstVals` | [10 20 30] |
| `winVals` | [0.15 0.25 0.35] |
| `candidates` | [0.4 0.5 0.6 0.7 0.8 0.9] |
| `initialThresholds` | eye/muscle/heart/line/channo/other fields, each 0.7 |
| `ICA_OPTIONS` | {'extended',1} |

Default sweeps are expensive and are examples, not validated optimal
thresholds. Start with one value per sweep to check your installation. The QC
score uses mean ERP amplitude divided by baseline sample variability, times
the square root of retained eligible epochs relative to the pre-ASR data.
Missing markers, empty input and wholly invalid ASR scores stop the pipeline.
Automated score selection does not replace visual review of cleaned signals.

## Outputs and tests

Outputs include `clean_<name>.set`, ASR and ICLabel tradeoff CSVs,
`ICLabel_dynamic_log.csv`, and `bad_channels_log.csv`. The final QC row is
recomputed from the saved processing result.

```matlab
results = runtests('/path/to/eeg_preprocess_BrainVision/tests');
assertSuccess(results);
addpath('/path/to/eeg_preprocess_BrainVision/tests');
smoke_brainvision; % generates synthetic inputs and runs the actual plugins
```

A synthetic BrainVision recording was also processed through actual filtering,
ASR, ICA, ICLabel and saving in the readiness audit. It used a small sweep and
128 ICA iterations; it verifies integration, not convergence or artifact
removal effectiveness on real study recordings.

## Downloadable synthetic example

[Run the bundled synthetic example](examples/synthetic/README.md) to check your setup against
included reference outputs. It contains actual input files, a one-command runner,
expected tables/plots, and numerical comparisons that report PASS or a mismatch.
The example guide links to the main-branch ZIP, including the readiness fixes.
