function tests=test_qc
tests=functiontests(localfunctions);
end
function testNoiseAndRetention(t)
addpath(fileparts(fileparts(mfilename('fullpath'))));
rng(4); E=eeg_emptyset; E.nbchan=1; E.srate=100; E.trials=1; E.pnts=1000;
E.xmin=0; E.xmax=9.99; E.times=(0:999)*10; E.chanlocs=struct('labels','Cz');
E.data=randn(1,1000); E.event=struct('type',{'stim','stim','stim'},'latency',{101,401,701});
E=eeg_checkset(E,'eventconsistency');
[snr,retained,n]=brainvision_qc(E,{'Cz'},[10 500],[-200 0],{'stim'},6);
verifyTrue(t,isfinite(snr)); verifyLessThan(t,snr,2);
verifyEqual(t,n,3); verifyEqual(t,retained,.5);
[snr,retained,n]=brainvision_qc(E,{'Cz'},[10 500],[-200 0],{'absent'},6);
verifyTrue(t,isnan(snr)); verifyEqual(t,n,0); verifyEqual(t,retained,0);
end
