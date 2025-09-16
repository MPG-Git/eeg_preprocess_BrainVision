%% preprocess_template.m
% Open-source EEG preprocessing template for BrainVision files (EEGLAB)
%
% Pipeline order (kept intact):
%  1) Load BrainVision files (.vhdr)
%  2) Select channels + re-reference (FCz reference added then average reref)
%  3) Filtering (e.g., 1–30 Hz)
%  4) ASR sweep (Flatline × ChannelCorr × Burst × Window)  [user‑tunable ranges]
%  5) ICA (runica)
%  6) ICLabel + dynamic threshold search  [user‑tunable ranges]
%  7) Save cleaned .set files
%  8) Log QC results to CSV
%
% Requirements:
%  - MATLAB R2019b+ (tested)
%  - EEGLAB (https://sccn.ucsd.edu/eeglab/index.php)
%  - EEGLAB plugins:
%       * ICLabel
%       * clean_rawdata   (for ASR; function: clean_artifacts)
%       * BrainVision I/O (bva-io; for pop_loadbv)
%
% Input:
%   Place .vhdr (and associated .eeg/.vmrk) under ./data/raw/ (can be nested)
%
% Output:
%   Cleaned .set files under ./data/clean/
%   Per-subject tradeoff CSVs (ASR + ICLabel) and a dynamic log CSV.
%
% Notes:
% - All threshold arrays below are **user‑tunable ranges**; they are *not*
%   “optimal defaults”. Adjust for your study, cap, and data quality.
% - QC score uses: score = snrVal * sqrt(trialKeep). You may replace this
%   with a custom metric for your project.
%
% -------------------------------------------------------------------------
% 1) USER CONFIG
% -------------------------------------------------------------------------

RAW_DIR   = './data/raw';       % <--- change if needed
CLEAN_DIR = './data/clean';     % <--- change if needed
if ~exist(CLEAN_DIR,'dir'); mkdir(CLEAN_DIR); end

% Channel locations (optional but recommended)
% Provide a standard montage file (e.g., standard_1005.elc or .ced)
CHANNEL_LOC_FILE = './resources/standard_1005.elc';  % set to [] to skip

% Channel list for a 32‑channel cap (example). Adapt to your cap.
SEL_CHANS = {'FP1','FP2','F3','F4','C3','C4','P3','P4','O1','O2', ...
             'F7','F8','T7','T8','P7','P8','Fz','Cz','Pz','Oz', ...
             'FC1','FC2','CP1','CP2','FC5','FC6','CP5','CP6','TP9','TP10','POz'};
REF_LABEL = 'FCz';  % FCz reference to be appended, then average reref

% Preprocessing settings
TARGET_SRATE   = 500;  % Hz (downsample target)
HP_CUTOFF_HZ   = 1;    % high-pass (Hz)
LP_CUTOFF_HZ   = 30;   % low-pass  (Hz)

% Epoch/QC settings
QC_EVENTS        = {'event1','event2'};  % <-- replace with your event codes
QC_BASE_MS       = [-200 0];
QC_WINDOW_MS     = [10 600];
QC_INNER_CHANNEL = []; % leave empty to auto-select via default_inner_channels()

% Optional: seed RNG for ICA reproducibility
% rng(42);

% Optional parallel (commented by default to keep template simple)
% parpool('local');  % requires Parallel Computing Toolbox

% -------------------------------------------------------------------------
% 2) DISCOVER FILES
% -------------------------------------------------------------------------
eeglab; close;   % initialize EEGLAB without GUI staying open
vhdrFiles = dir(fullfile(RAW_DIR, '**', '*.vhdr'));
fprintf('Found %d BrainVision files under %s\n', numel(vhdrFiles), RAW_DIR);

% -------------------------------------------------------------------------
% 3) MAIN LOOP
% -------------------------------------------------------------------------
for k = 1:numel(vhdrFiles)
    % ---- Paths / Subject ID
    thisVhdr = fullfile(vhdrFiles(k).folder, vhdrFiles(k).name);
    [~, base, ~] = fileparts(thisVhdr);
    subjID = base;  % neutral ID
    fprintf('\n==== Subject: %s ====\n', subjID);

    % ---- Load
    EEG = pop_loadbv(vhdrFiles(k).folder, vhdrFiles(k).name);

    % ---- Channel selection & reference
    EEG = pop_select(EEG, 'channel', SEL_CHANS);
    if ~isempty(CHANNEL_LOC_FILE) && exist(CHANNEL_LOC_FILE,'file')
        EEG = pop_chanedit(EEG, 'append', numel(SEL_CHANS), 'changefield', {numel(SEL_CHANS)+1, 'labels', REF_LABEL}, ...
            'lookup', CHANNEL_LOC_FILE, 'setref', {'1:' num2str(numel(SEL_CHANS)+1), REF_LABEL});
    else
        EEG = pop_chanedit(EEG, 'append', numel(SEL_CHANS), 'changefield', {numel(SEL_CHANS)+1, 'labels', REF_LABEL}, ...
            'setref', {'1:' num2str(numel(SEL_CHANS)+1), REF_LABEL});
    end
    EEG = pop_reref(EEG, [], 'refloc', struct('labels',{REF_LABEL},'ref',{REF_LABEL}));  % average reref with FCz present

    % ---- Reorder (optional sanity to enforce a standard order)
    allChans = [SEL_CHANS, {REF_LABEL}];
    [~, idx] = ismember(allChans, {EEG.chanlocs.labels});
    EEG.chanlocs = EEG.chanlocs(idx);
    EEG.data     = EEG.data(idx,:);
    EEG = eeg_checkset(EEG);

    % ---- Downsample & remove DC
    EEG = pop_resample(EEG, TARGET_SRATE);
    elecMean = mean(EEG.data, 2);
    EEG.data = EEG.data - repmat(elecMean, 1, size(EEG.data, 2));

    % ---- Filtering
    if ~isempty(HP_CUTOFF_HZ)
        EEG = pop_eegfiltnew(EEG, 'locutoff', HP_CUTOFF_HZ);
    end
    if ~isempty(LP_CUTOFF_HZ)
        EEG = pop_eegfiltnew(EEG, 'hicutoff', LP_CUTOFF_HZ);
    end
    EEG = eeg_checkset(EEG);
    originalEEG = EEG;  % keep pre‑ASR copy for interpolation bookkeeping

    % ---------------------------------------------------------------------
    % 4) ASR SWEEP  [user‑tunable ranges]
    % ---------------------------------------------------------------------
    % The following arrays define the search space for ASR's parameters.
    % Adjust ranges according to your data quality:
    flatlineVals = [3 5 8];          % seconds of flatline allowed
    chanCorrVals = [0.60 0.70 0.80 0.90];  % bad channel (minimum correlation)
    burstVals    = [10 20 30];       % SD threshold for bursts
    winVals      = [0.15 0.25 0.35]; % fraction of windows allowed as bad

    resultsASR = table();
    bestScore = -Inf; bestF = flatlineVals(1); bestC = chanCorrVals(1);
    bestB = burstVals(1); bestW = winVals(1);

    for f = flatlineVals
        for cc = chanCorrVals
            for b = burstVals
                for w = winVals
                    EEGtmp = clean_artifacts(EEG, ...
                        'FlatlineCriterion', f, ...
                        'ChannelCriterion',  cc, ...
                        'LineNoiseCriterion','off', ...
                        'Highpass','off', ...
                        'BurstCriterion',    b, ...
                        'WindowCriterion',   w, ...
                        'BurstRejection','off', ...
                        'Distance','Euclidian', ...
                        'WindowCriterionTolerances',[-Inf 7]);

                    % --- QC metric: SNR × sqrt(trial retention)
                    coreChans = QC_INNER_CHANNEL;
                    if isempty(coreChans)
                        coreChans = default_inner_channels(EEG.nbchan);
                    end
                    [snrVal, trialKeep] = compute_qc(EEGtmp, coreChans, QC_WINDOW_MS, QC_BASE_MS, QC_EVENTS);
                    score = snrVal * sqrt(trialKeep);  % <-- user‑definable metric

                    newRow = table({subjID}, f, cc, b, w, snrVal, trialKeep, score, ...
                        'VariableNames', {'Subject','FlatlineCriterion','ChannelCriterion','BurstCriterion','WindowCriterion','SNR','TrialKeep','Score'});
                    resultsASR = [resultsASR; newRow]; %#ok<AGROW>

                    if score > bestScore
                        bestScore = score; bestF = f; bestC = cc; bestB = b; bestW = w;
                    end
                end
            end
        end
    end

    fprintf('Best ASR for %s: Flatline=%g s, ChannelCorr=%.2f, Burst=%d, Window=%.2f (Score=%.3f)\n', ...
        subjID, bestF, bestC, bestB, bestW, bestScore);

    % Apply best ASR
    EEG = clean_artifacts(EEG, ...
        'FlatlineCriterion', bestF, ...
        'ChannelCriterion',  bestC, ...
        'LineNoiseCriterion','off', ...
        'Highpass','off', ...
        'BurstCriterion',    bestB, ...
        'WindowCriterion',   bestW, ...
        'BurstRejection','off', ...
        'Distance','Euclidian', ...
        'WindowCriterionTolerances',[-Inf 7]);

    % Save ASR tradeoff
    asrFile = fullfile(CLEAN_DIR, sprintf('%s_ASR_tradeoff.csv', subjID));
    writetable(resultsASR, asrFile);

    % ---- Track removed channels (in ASR) and interpolate back
    [~, ia, ib] = intersect({EEG.chanlocs.labels}, {originalEEG.chanlocs.labels}, 'stable');
    removed = {originalEEG.chanlocs.labels};
    removed(ib) = [];
    badChannel(k).subjectID = subjID; %#ok<SAGROW>
    badChannel(k).nChan     = numel(removed);
    badChannel(k).chan      = strjoin(removed, ', ');

    EEG = pop_interp(EEG, originalEEG.chanlocs, 'spherical');
    EEG = pop_reref(EEG, []);  % average reref after interp

    % ---------------------------------------------------------------------
    % 5) ICA
    % ---------------------------------------------------------------------
    dataRank = sum(eig(cov(double(EEG.data'))) > 1E-6); % consistent with pop_runica()
    EEG = pop_runica(EEG, 'icatype','runica','pca',dataRank,'options',{'extended',1});
    EEG = eeg_checkset(EEG, 'ica');

    % ---------------------------------------------------------------------
    % 6) ICLABEL + dynamic thresholds  [user‑tunable ranges]
    % ---------------------------------------------------------------------
    EEG = iclabel(EEG, 'default');
    probs  = EEG.etc.ic_classification.ICLabel.classifications; % [nIC x 7]
    labels = EEG.etc.ic_classification.ICLabel.classes;         % cellstr label order

    % ICLabel classes to sweep & candidate thresholds (user‑tunable)
    classes    = {'eye','muscle','heart','line','channo','other'};
    candidates = [0.4 0.5 0.6 0.7 0.8 0.9];

    % Greedy per‑class search around defaults
    bestThresh = struct('eye',0.70,'muscle',0.70,'heart',0.70,'line',0.70,'channo',0.70,'other',0.70);
    allResults = table();

    for ci = 1:numel(classes)
        cls = classes{ci};
        bestLocalScore = -Inf;
        bestVal = bestThresh.(cls);

        for c = candidates
            tmpTh = bestThresh; tmpTh.(cls) = c;
            EEGtmp = apply_thresholds(EEG, probs, labels, tmpTh);

            coreChans = QC_INNER_CHANNEL;
            if isempty(coreChans)
                coreChans = default_inner_channels(EEG.nbchan);
            end
            [snrVal, trialKeep] = compute_qc(EEGtmp, coreChans, QC_WINDOW_MS, QC_BASE_MS, QC_EVENTS);
            score = snrVal * sqrt(trialKeep);

            allResults = [allResults; table({subjID},{cls},c,snrVal,trialKeep,score, ...
                'VariableNames',{'Subject','Class','Threshold','SNR','TrialKeep','Score'})]; %#ok<AGROW>

            if score > bestLocalScore
                bestLocalScore = score;
                bestVal = c;
            end
        end
        bestThresh.(cls) = bestVal;
    end

    % Final rejection
    rmIdx = find_ic_to_remove(probs, labels, bestThresh);
    fprintf('Removing %d ICs for %s: %s\n', numel(rmIdx), subjID, mat2str(rmIdx));
    if ~isempty(rmIdx); EEG = pop_subcomp(EEG, rmIdx, 0, 1); end
    EEG.icaact = []; EEG = eeg_checkset(EEG,'ica');

    % ---- Log thresholds
    logFile = fullfile(CLEAN_DIR, 'ICLabel_dynamic_log.csv');
    coreChans = QC_INNER_CHANNEL;
    if isempty(coreChans); coreChans = default_inner_channels(EEG.nbchan); end
    chanStr = strjoin(coreChans, ', ');
    logRow = table({subjID}, bestThresh.eye, bestThresh.muscle, bestThresh.heart, ...
        bestThresh.line, bestThresh.channo, bestThresh.other, ...
        bestLocalScore, snrVal, trialKeep, {chanStr}, ...
        'VariableNames', {'Subject','Eye','Muscle','Heart','Line','Channo','Other','Score','SNR','TrialKeep','QC_Channels'});
    if ~isfile(logFile); writetable(logRow, logFile); else; writetable(logRow, logFile, 'WriteMode','Append'); end

    % Save per‑subject ICLabel tradeoff
    tradeoffFile = fullfile(CLEAN_DIR, sprintf('%s_ICLabel_tradeoff.csv', subjID));
    writetable(allResults, tradeoffFile);

    % ---------------------------------------------------------------------
    % 7) SAVE CLEANED DATA
    % ---------------------------------------------------------------------
    EEG = eeg_checkset(EEG);
    outName = sprintf('clean_%s.set', subjID);
    EEG = pop_saveset(EEG, 'filename', outName, 'filepath', CLEAN_DIR);

end

% -------------------------------------------------------------------------
% 8) SAVE BAD‑CHANNEL LOG (optional summary across subjects)
% -------------------------------------------------------------------------
if exist('badChannel','var') && ~isempty(badChannel)
    Tbad = struct2table(badChannel);
    writetable(Tbad, fullfile(CLEAN_DIR, 'bad_channels_log.csv'));
end

fprintf('\n✅ Done. Clean datasets & CSVs are in: %s\n', CLEAN_DIR);

%% ===================== HELPERS =====================

function EEGout = apply_thresholds(EEGin, probs, labels, th)
% APPLY_THRESHOLDS  Remove ICs based on ICLabel probabilities + thresholds.
% EEGout = apply_thresholds(EEGin, probs, labels, th)
%
% Inputs:
%   EEGin  - EEGLAB dataset (with ICA and ICLabel already run)
%   probs  - ICLabel probabilities matrix (nIC x 7)
%   labels - ICLabel class names (1x7 cell), e.g. {'brain','muscle','eye',...}
%   th     - struct with fields: eye, muscle, heart, line, channo, other (0..1)
%
% Output:
%   EEGout - dataset after component rejection
%
% Note: ICLabel column order can vary by version; we resolve indexes from
% 'labels' where possible, and otherwise fall back to a common convention.

idx = map_iclabel_indices(labels);
rmIdx = find( probs(:,idx.eye)    >= th.eye    | ...
              probs(:,idx.muscle) >= th.muscle | ...
              probs(:,idx.heart)  >= th.heart  | ...
              probs(:,idx.line)   >= th.line   | ...
              probs(:,idx.channo) >= th.channo | ...
              probs(:,idx.other)  >= th.other );

EEGout = EEGin;
if ~isempty(rmIdx)
    EEGout = pop_subcomp(EEGin, rmIdx, 0, 1);
end
EEGout.icaact = [];
EEGout = eeg_checkset(EEGout,'ica');
end

function idx = map_iclabel_indices(labels)
% MAP_ICLABEL_INDICES  Map class names to column indices in ICLabel output.
% Returns struct with fields: brain, muscle, eye, heart, line, channo, other.
% Falls back to the typical order if 'labels' is unavailable.
idx = struct('brain',1,'muscle',2,'eye',3,'heart',4,'line',5,'channo',6,'other',7);
if nargin<1 || isempty(labels); return; end
names = lower(string(labels));
lookup = containers.Map({'brain','muscle','eye','heart','line noise','channel noise','other'}, ...
                        {'brain','muscle','eye','heart','line','channo','other'});
for c = 1:numel(names)
    key = char(names(c));
    if lookup.isKey(key)
        f = lookup(key);
        idx.(f) = c;
    end
end
end

function [snrVal, trialKeep] = compute_qc(EEG, chanLabels, erpWindow, baseWindow, events)
% COMPUTE_QC  Compute QC metrics: ERP SNR and trial retention.
%
% [snrVal, trialKeep] = compute_qc(EEG, chanLabels, erpWindow, baseWindow, events)
%
% Inputs:
%   EEG         - EEGLAB dataset (epoched or continuous; we epoch here)
%   chanLabels  - cellstr of channel labels to evaluate (e.g., {'Fz','FCz','Cz'})
%   erpWindow   - [start end] ms window for ERP "signal"
%   baseWindow  - [start end] ms baseline for "noise" std estimate
%   events      - cellstr of event codes for epoching (e.g., {'S  6','S  7'})
%
% Outputs:
%   snrVal      - mean |signal|/noise across selected channels
%   trialKeep   - proportion of trials retained after cleaning
%
% Notes:
% - This is a **template** QC; replace with your own metric if needed.
% - If events are absent or epoching fails, returns NaN, 0.

if nargin < 5 || isempty(events)
    events = {'event1','event2'};  % placeholder
end

try
    EEGe = pop_epoch(EEG, events, [min(baseWindow(1), erpWindow(1))/1000, max(baseWindow(2), erpWindow(2))/1000], 'epochinfo','yes');
    EEGe = pop_rmbase(EEGe, baseWindow);
catch
    snrVal = NaN; trialKeep = 0; return
end

trialKeep = EEGe.trials / max(1, EEG.trials);

labels = {EEGe.chanlocs.labels};
chanIdx = find(ismember(lower(labels), lower(chanLabels)));
if isempty(chanIdx); snrVal = NaN; return; end

tBase = EEGe.times >= baseWindow(1) & EEGe.times <= baseWindow(2);
tSig  = EEGe.times >= erpWindow(1)  & EEGe.times <= erpWindow(2);

snrs = zeros(1, numel(chanIdx));
for i = 1:numel(chanIdx)
    noise  = std(mean(EEGe.data(chanIdx(i), tBase, :), 2), 0, 'all');
    signal = mean(mean(EEGe.data(chanIdx(i), tSig,  :), 2), 'all');
    snrs(i) = abs(signal) / max(realmin, noise);
end
snrVal = mean(snrs, 'omitnan');
end

function chans = default_inner_channels(nChans)
% DEFAULT_INNER_CHANNELS  Return a set of inner electrodes for QC based on cap size.
% chans = default_inner_channels(nChans)
%
% This excludes outermost ring(s) typically prone to artifacts. Adjust as needed.
switch nChans
    case {30,31,32}
        chans = {'Fz','Cz','Pz','Oz','POz','FC1','FC2','CP1','CP2','P1','P2'};
    case {60,61,62,63,64}
        chans = {'Fz','Cz','Pz','Oz','POz','AFz','FCz','CPz','F1','F2','FC1','FC2','C1','C2','CP1','CP2','P1','P2'};
    case {124,125,126,127,128}
        chans = {'Fz','Cz','Pz','Oz','POz','AFz','FCz','CPz','Fpz','F1','F2','F3','F4','FC1','FC2','C1','C2','CP1','CP2','P1','P2'};
    otherwise
        chans = {'Fz','Cz','Pz','Oz'}; % conservative fallback
end
end

function rmIdx = find_ic_to_remove(probs, labels, th)
% FIND_IC_TO_REMOVE  Compute removal indices given thresholds and ICLabel outputs.
idx = map_iclabel_indices(labels);
rmIdx = find( probs(:,idx.eye)    >= th.eye    | ...
              probs(:,idx.muscle) >= th.muscle | ...
              probs(:,idx.heart)  >= th.heart  | ...
              probs(:,idx.line)   >= th.line   | ...
              probs(:,idx.channo) >= th.channo | ...
              probs(:,idx.other)  >= th.other );
end

function [GA, times, chanlocs, fileList] = grand_average_erp(folderPath, events, epochWin, baseMs)
% GRAND_AVERAGE_ERP  Compute grand-average ERP across all .set files in a folder.
%
% [GA, times, chanlocs, fileList] = grand_average_erp(folderPath, events, epochWin, baseMs)
% Inputs:
%   folderPath - path containing .set files
%   events     - cellstr of event codes to epoch on
%   epochWin   - [start end] in seconds (e.g., [-0.2 0.7])
%   baseMs     - [start end] in ms for baseline removal
% Outputs:
%   GA         - grand-average ERP (nChan x nTime)
%   times      - time vector
#   chanlocs   - EEG.chanlocs from the first usable file
%   fileList   - list of files included
files = dir(fullfile(folderPath, '*.set'));
allSubj = []; fileList = {}; times = []; chanlocs = [];
for i = 1:numel(files)
    try
        EEG = pop_loadset('filename', files(i).name, 'filepath', files(i).folder);
        evtypes = cellfun(@(x) strtrim(char(x)), {EEG.event.type}, 'UniformOutput', false);
        if ~any(ismember(evtypes, strtrim(events))); warning('No matching events: %s', files(i).name); continue; end
        EEGe = pop_epoch(EEG, events, epochWin, 'epochinfo','yes');
        EEGe = pop_rmbase(EEGe, baseMs);
    catch ME
        warning('Skipping %s (%s)', files(i).name, ME.message); continue
    end
    erp = mean(EEGe.data, 3);
    if isempty(allSubj)
        allSubj = reshape(erp, size(erp,1), size(erp,2), 1);
        times = EEGe.times; chanlocs = EEGe.chanlocs;
    else
        if size(erp,2) ~= size(allSubj,2); warning('Time length mismatch: %s', files(i).name); continue; end
        allSubj(:,:,end+1) = erp; %#ok<AGROW>
    end
    fileList{end+1} = files(i).name; %#ok<AGROW>
end
if isempty(allSubj); error('No usable ERPs found in %s', folderPath); end
GA = mean(allSubj, 3, 'omitnan');
end
