function [snrVal,trialKeep,nTrials]=brainvision_qc(EEG,chanLabels,erpWindow,baseWindow,events,originalTrials)
% ERP mean amplitude / single-trial baseline SD, and eligible-epoch retention.
% The denominator uses baseline samples, not the baseline means (which are
% zero after baseline correction). Compare counts with the pre-cleaning data.
snrVal=NaN; trialKeep=0; nTrials=0;
try
    E=pop_epoch(EEG,events,[min(baseWindow(1),erpWindow(1)) max(baseWindow(2),erpWindow(2))]/1000,'epochinfo','yes');
    E=pop_rmbase(E,baseWindow);
catch
    return;
end
nTrials=E.trials;
if isempty(originalTrials), originalTrials=nTrials; end
trialKeep=min(1,nTrials/max(1,originalTrials));
idx=find(ismember(lower(string({E.chanlocs.labels})),lower(string(chanLabels))));
base=E.times>=baseWindow(1) & E.times<=baseWindow(2);
signal=E.times>=erpWindow(1) & E.times<=erpWindow(2);
if isempty(idx) || ~any(base) || ~any(signal), return; end
values=nan(1,numel(idx));
for k=1:numel(idx)
    noise=std(double(E.data(idx(k),base,:)),0,'all');
    amplitude=abs(mean(double(E.data(idx(k),signal,:)),'all'));
    if noise>eps, values(k)=amplitude/noise; end
end
snrVal=mean(values,'omitnan');
end
