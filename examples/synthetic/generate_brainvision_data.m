function generate_brainvision_data(destination)
if nargin<1, destination=fullfile(fileparts(mfilename('fullpath')),'data'); end
assert(~isfolder(destination),'Choose a new destination'); mkdir(destination);
oldRng=rng; cleanup=onCleanup(@()rng(oldRng)); rng(8); raw=destination;
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

end
