function smoke_brainvision
% Integration test: requires the actual EEGLAB plugins listed in README.
addpath(fileparts(fileparts(mfilename('fullpath'))));
root=tempname; raw=fullfile(root,'raw'); mkdir(raw); rng(8);
names={'F3','F4','C3','C4','Fz','Cz','Pz','Oz'};
n=12000; time=(0:n-1)/100;
sources=sin(2*pi*[3;7;10;15]*time);
data=randn(8,4)*sources+.3*randn(8,n); markers=201:200:n-199;
for latency=markers
    data=data+linspace(1,2,8)'*exp(-(((1:n)-latency-30)/8).^2);
end
fid=fopen(fullfile(raw,'synthetic.eeg'),'w','ieee-le'); fwrite(fid,single(data),'single'); fclose(fid);
fid=fopen(fullfile(raw,'synthetic.vhdr'),'w');
fprintf(fid,['Brain Vision Data Exchange Header File Version 1.0\n[Common Infos]\n' ...
 'DataFile=synthetic.eeg\nMarkerFile=synthetic.vmrk\nDataFormat=BINARY\n' ...
 'DataOrientation=MULTIPLEXED\nNumberOfChannels=8\nSamplingInterval=10000\n' ...
 '[Binary Infos]\nBinaryFormat=IEEE_FLOAT_32\n[Channel Infos]\n']);
for k=1:8, fprintf(fid,'Ch%d=%s,,1,uV\n',k,names{k}); end
fclose(fid);
fid=fopen(fullfile(raw,'synthetic.vmrk'),'w');
fprintf(fid,['Brain Vision Data Exchange Marker File, Version 1.0\n[Common Infos]\n' ...
 'DataFile=synthetic.eeg\n[Marker Infos]\n']);
for k=1:numel(markers), fprintf(fid,'Mk%d=Stimulus,S  1,%d,1,0\n',k,markers(k)); end
fclose(fid);
c=struct('RAW_DIR',raw,'CLEAN_DIR',fullfile(root,'clean'), ...
 'QC_EVENTS',{{'S  1'}},'SEL_CHANS',{names},'TARGET_SRATE',100, ...
 'flatlineVals',5,'chanCorrVals',0,'burstVals',100,'winVals',1, ...
 'candidates',.99,'seed',7,'ICA_OPTIONS',{{'extended',1,'maxsteps',128}});
c.initialThresholds=struct('eye',1,'muscle',1,'heart',1,'line',1,'channo',1,'other',1);
run_brainvision_preprocessing(c);
E=pop_loadset('filename','clean_synthetic.set','filepath',c.CLEAN_DIR);
assert(E.nbchan==9 && E.pnts>0 && all(isfinite(E.data),'all'));
qc=readtable(fullfile(c.CLEAN_DIR,'ICLabel_dynamic_log.csv'));
assert(all(isfinite(qc.SNR)) && all(qc.TrialKeep>0 & qc.TrialKeep<=1));
assert(all(abs(mean(double(E.data),1))<1e-5));
assert(isfield(E.etc,'ic_classification'));
fprintf('PASS: BrainVision integration. Artifacts: %s\n',root);
end
