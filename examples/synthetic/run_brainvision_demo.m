function run_brainvision_demo(out)
if nargin<1, out=''; end
[here,out,cleanup]=demo_prepare(mfilename('fullpath'),out); %#ok<ASGLU>
addpath(fileparts(fileparts(here)));
names={'F3','F4','C3','C4','Fz','Cz','Pz','Oz'};
c=struct('RAW_DIR',fullfile(here,'data'),'CLEAN_DIR',out, ...
 'QC_EVENTS',{{'S  1'}},'SEL_CHANS',{names},'TARGET_SRATE',100, ...
 'flatlineVals',5,'chanCorrVals',0,'burstVals',100,'winVals',1, ...
 'candidates',.99,'seed',7,'ICA_OPTIONS',{{'extended',1,'maxsteps',128}});
c.initialThresholds=struct('eye',1,'muscle',1,'heart',1,'line',1,'channo',1,'other',1);
run_brainvision_preprocessing(c);
E=pop_loadset('filename','clean_synthetic.set','filepath',out);
assert(E.nbchan==9 && E.pnts>0 && all(isfinite(E.data),'all'));
qc=readtable(fullfile(out,'ICLabel_dynamic_log.csv'));
assert(all(isfinite(qc.SNR)) && all(qc.TrialKeep>0 & qc.TrialKeep<=1));
avgError=max(abs(mean(double(E.data),1))); assert(avgError<1e-5);
assert(isfield(E.etc,'ic_classification'));
fig=figure; fc=onCleanup(@()close(fig)); %#ok<NASGU>
plot((0:E.pnts-1)/E.srate,double(E.data(1:3,:))'); xlim([0 10]);
xlabel('Time (seconds)'); ylabel('Cleaned EEG (microvolts)'); legend({E.chanlocs(1:3).labels}); grid on;
print(fig,fullfile(out,'cleaned_preview.png'),'-dpng','-r120');
demo_verify(here,out,{'Channels','SamplingRateHz','AverageReferenceMaxResidual','TrialKeep','SNR'}, ...
 [E.nbchan,E.srate,avgError,mean(qc.TrialKeep),mean(qc.SNR)]);
end
