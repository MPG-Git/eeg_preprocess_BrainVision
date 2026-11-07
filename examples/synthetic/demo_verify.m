function demo_verify(here,out,names,values)
% Numeric reference comparisons only; image rendering and file bytes may differ.
actual=table(string(names(:)),values(:),'VariableNames',{'Metric','Value'});
writetable(actual,fullfile(out,'metrics.csv'));
refFile=fullfile(here,'expected','metrics.csv');
assert(isfile(refFile),'demo:MissingReference','Missing bundled expected/metrics.csv. Results were saved, but verification cannot pass.');
ref=readtable(refFile,'TextType','string');
assert(isequal(actual.Metric,ref.Metric),'Metric names/order differ from reference');
delta=abs(actual.Value-ref.Value);
pass=isfinite(actual.Value) & delta<=ref.AbsTolerance;
comparison=table(actual.Metric,actual.Value,ref.Value,ref.AbsTolerance,delta,pass, ...
    'VariableNames',{'Metric','Actual','Expected','AbsTolerance','AbsoluteDifference','Pass'});
writetable(comparison,fullfile(out,'comparison.csv')); disp(comparison);
assert(all(pass),'demo:ComparisonFailed','Example differs from reference; see comparison.csv and the version/tolerance notes.');
fid=fopen(fullfile(out,'PASS.txt'),'w'); fprintf(fid,'PASS: bundled synthetic example matched its documented checks.\n'); fclose(fid);
fprintf('PASS: synthetic example. Results: %s\n',out);
end
