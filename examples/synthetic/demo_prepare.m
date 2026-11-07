function [here,out,cleanup] = demo_prepare(functionPath,out)
% Isolate generated files and restore the caller's folder/path/graphics state.
here=fileparts(functionPath);
if isempty(out), out=fullfile(here,'output'); end
if isfolder(out) || isfile(out)
    error('demo:OutputExists','Choose a NEW output folder; this path already exists: %s',out);
end
oldFolder=pwd; oldPath=path; oldVisibility=get(groot,'defaultFigureVisible'); oldRng=rng;
mkdir(out); cd(out); out=pwd; cd(oldFolder);
cleanup=onCleanup(@() restore(oldFolder,oldPath,oldVisibility,oldRng));
set(groot,'defaultFigureVisible','off');
end
function restore(folder,savedPath,visibility,savedRng)
cd(folder); path(savedPath); set(groot,'defaultFigureVisible',visibility); rng(savedRng);
end
