%% BrainVision preprocessing example: edit these study-specific settings.
% Initialize EEGLAB before running. See README.md for required plugins.
root=fileparts(mfilename('fullpath'));
config=struct;
config.RAW_DIR=fullfile(root,'data','raw');
config.CLEAN_DIR=fullfile(root,'data','clean');
config.QC_EVENTS={'event1','event2'}; % Replace with your BrainVision markers.
config.REF_LABEL='FCz'; % Omitted recording reference; use '' if none to add.
config.seed=42;
% Optional: config.SEL_CHANS, config.CHANNEL_LOC_FILE, config.TARGET_SRATE,
% config.flatlineVals, config.chanCorrVals, config.burstVals, config.winVals,
% config.candidates, config.QC_INNER_CHANNEL, config.ICA_OPTIONS.
run_brainvision_preprocessing(config);
