# EEG Preprocessing Template (MATLAB + EEGLAB)

A clean, **GitHub-ready** template for preprocessing EEG BrainVision datasets. It generalizes an internal lab script into an open-source, documented pipeline with user-tunable parameter sweeps and QC logging.

## What it does (pipeline order)

1. Load **BrainVision** files (`.vhdr`)
2. Select channels and add **FCz** reference; then **average re-reference**
3. **Filter** (default: 1–30 Hz)
4. **ASR** sweep (Flatline × ChannelCorr × Burst × Window) — **user-tunable ranges**
5. **ICA** (runica)
6. **ICLabel** + **dynamic threshold search** — **user-tunable ranges**
7. Save cleaned **`.set`** files
8. Log **QC results** to CSV (ASR & ICLabel tradeoffs + dynamic log)

---

## Requirements

- **MATLAB** R2019b or newer (tested)
- **EEGLAB** (latest recommended)
- EEGLAB **plugins**:
  - **ICLabel** (component classification)
  - **clean_rawdata** (ASR; provides `clean_artifacts`)
  - **BrainVision I/O** (**bva-io**) for `pop_loadbv`
- (Optional) **Parallel Computing Toolbox** if you plan to parallelize your own modifications

Install EEGLAB and plugins from the EEGLAB Plugin Manager or their GitHub pages. See [`requirements.txt`](requirements.txt) for a concise list.

---

## Folder layout

```
.
├─ preprocess_template.m        # main script (edit USER CONFIG section)
├─ requirements.txt             # MATLAB + EEGLAB plugin requirements
├─ resources/
│  └─ standard_1005.elc         # (recommended) channel locations file (add your own)
├─ data/
│  ├─ raw/                      # put BrainVision .vhdr/.vmrk/.eeg here (can be nested)
│  └─ clean/                    # outputs (.set + CSVs) are written here
```

You can change `RAW_DIR` and `CLEAN_DIR` at the top of the script.

---

## Input and outputs

**Input:** BrainVision files (`.vhdr` with matching `.vmrk` and `.eeg`) placed under `./data/raw/` (subfolders allowed).

**Outputs (in `./data/clean/`):**
- `clean_<SUBJECT>.set` — cleaned EEGLAB dataset per subject
- `<SUBJECT>_ASR_tradeoff.csv` — QC table for every ASR parameter combination tried
- `<SUBJECT>_ICLabel_tradeoff.csv` — QC table for every ICLabel threshold candidate tried
- `ICLabel_dynamic_log.csv` — one-row-per-subject summary of the ICLabel thresholds chosen and QC metrics
- `bad_channels_log.csv` — summary (per subject) of channels removed by ASR and then interpolated back

---

## User‑tunable parameters

The script declares **ranges** for parameter sweeps. These are **not optimal defaults** — tune them for your dataset.

### ASR ranges (edit in `preprocess_template.m`)
- `flatlineVals = [3 5 8];` *(seconds)*
- `chanCorrVals = [0.60 0.70 0.80 0.90];` *(minimum channel correlation)*
- `burstVals    = [10 20 30];` *(burst SD threshold)*
- `winVals      = [0.15 0.25 0.35];` *(fraction of bad windows)*

### ICLabel threshold candidates
- `classes = {'eye','muscle','heart','line','channo','other'};`
- `candidates = [0.4 0.5 0.6 0.7 0.8 0.9];` *(per-class probability threshold)*

> The selection is done by maximizing a QC score per subject (see below). You can narrow/expand ranges, fix some parameters, or change the search strategy.

---

## QC metric (score)

By default we compute:
```
score = SNR × sqrt(trialKeep)
```
- **SNR** is computed on user‑selected channels and time windows (see `QC_INNER_CHANNEL`, `QC_BASE_MS`, `QC_WINDOW_MS`).
- **trialKeep** is the fraction of trials retained after cleaning.
- This is a **template**; you can replace it with your own quality metric inside `compute_qc()` or where `score` is calculated.

You also need to set meaningful **event codes** for epoching in QC:
```matlab
QC_EVENTS = {'event1','event2'};  % replace with your triggers
```

---

## Channel selection and reference

The template includes a 32‑channel example (`SEL_CHANS`) and appends **FCz** to re-reference. Adapt `SEL_CHANS` and the reference to your cap. You can also supply a channel locations file (`CHANNEL_LOC_FILE`), e.g., `resources/standard_1005.elc`.

---

## Helper functions (kept & generalized)

- `compute_qc(EEG, chanLabels, erpWindow, baseWindow, events)` — returns `snrVal, trialKeep`.  
  *Replace events and windows for your task.*
- `apply_thresholds(EEG, probs, labels, th)` — removes ICs based on ICLabel scores.  
  *Resolves ICLabel column indices from `labels` to be robust to plugin versions.*
- `default_inner_channels(nChans)` — suggests inner electrodes for QC by cap size.  
  *Adjust to your montage.*
- `grand_average_erp(folderPath, events, epochWin, baseMs)` — computes a grand-average ERP over saved `.set` files (optional).

Each function includes docstrings with inputs/outputs.

---

## How to run

1. Install EEGLAB and plugins (ICLabel, clean_rawdata, bva-io).
2. Put your BrainVision files in `./data/raw/`.
3. Edit the **USER CONFIG** section at the top of `preprocess_template.m`:
   - `RAW_DIR`, `CLEAN_DIR`
   - `SEL_CHANS`, `REF_LABEL`, `CHANNEL_LOC_FILE`
   - `QC_EVENTS`, `QC_BASE_MS`, `QC_WINDOW_MS`
   - ASR and ICLabel ranges if needed
4. In MATLAB:
   ```matlab
   eeglab;  % ensure EEGLAB is on the path
   run('preprocess_template.m')
   ```

The script loops through all `.vhdr` files it finds recursively and writes outputs to `./data/clean/`.

---

## Notes & tips

- **ICLabel class order** can vary; this template reads the class names from the ICLabel output to map indices safely.
- If you use **parallel** execution, ensure that all workers have EEGLAB and plugin paths available (e.g., add `addpath` inside `parfor`).
- For multi-cap projects, consider branching settings by `EEG.nbchan` inside the loop.
- If you do **task-specific QC**, plug your event codes and windows into `QC_EVENTS` and `compute_qc()`.

---

## License

MIT — see `LICENSE` (add one if you publish).

If you use this template in a paper or project, citing EEGLAB and relevant plugins is appreciated.
