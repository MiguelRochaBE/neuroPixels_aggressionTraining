%% run_alignatlasdata.m
% Prepare inputs and run alignatlasdata
% Assumes Kilosort/Phy output, histology output, and Allen CCF are available

%% ------------------------------------------------------------------------
% USER-DEFINED PATHS
%% ------------------------------------------------------------------------

% Root data directory
dataRoot = 'D:\EphysData\Mouse123\Session01';

% Histology output (BrainGlobe CSV or AP_histology probe_ccf output)
histologyPath = fullfile(dataRoot, 'histology');

% Allen CCF repository path
AllenCCFPath = 'D:\AllenCCF';   % path to cortex-lab/allenCCF repo

% Kilosort output directory
ksDir = fullfile(dataRoot, 'kilosort');

% Optional LFP directory (leave empty [] if unused)
LFPDir = [];  % e.g. fullfile(dataRoot,'lfp')

%% ------------------------------------------------------------------------
% LOAD HISTOLOGY INFO
%% ------------------------------------------------------------------------

% Example: BrainGlobe CSV output
histFiles = dir(fullfile(histologyPath, '*.csv'));

% If single-shank probe
if numel(histFiles) == 1
    histinfo = readtable(fullfile(histFiles(1).folder, histFiles(1).name));
else
    % Multi-shank probe: each cell is one shank
    histinfo = cell(numel(histFiles),1);
    for iF = 1:numel(histFiles)
        histinfo{iF} = readtable(fullfile(histFiles(iF).folder, histFiles(iF).name));
    end
end

%% ------------------------------------------------------------------------
% OPTIONAL: LOAD TRACK COORDINATES (BrainGlobe .npy)
%% ------------------------------------------------------------------------

trackcoordinates = [];

npyFiles = dir(fullfile(histologyPath, '*.npy'));
if ~isempty(npyFiles)
    trackcoordinates = readNPY(fullfile(npyFiles(1).folder, npyFiles(1).name));
end

%% ------------------------------------------------------------------------
% LOAD SPIKE DATA (KILOSORT)
%% ------------------------------------------------------------------------

% Requires Nick Steinmetz sp package on MATLAB path
% https://github.com/cortex-lab/spikes
sp = loadKSdir(ksDir);

%% ------------------------------------------------------------------------
% LOAD CLUSTER INFO
%% ------------------------------------------------------------------------

% Minimal cluster info required by alignatlasdata
clusinfo = struct();
clusinfo.cluster_id = unique(sp.clu);    % cluster IDs
clusinfo.depth = sp.clusterDepths;        % depth per cluster (µm)
clusinfo.channel = sp.clusterChannels;    % channel per cluster

%% ------------------------------------------------------------------------
% ALIGNMENT OPTIONS
%% ------------------------------------------------------------------------

removenoise   = 1;   % remove noise clusters
surfacefirst = 0;   % deepest index = deepest in brain
treeversion  = 2;   % Allen tree version (2 = 2017)

%% ------------------------------------------------------------------------
% RUN ALIGNMENT
%% ------------------------------------------------------------------------

Depth2AreaPerUnit = alignatlasdata( ...
    histinfo, ...
    AllenCCFPath, ...
    sp, ...
    clusinfo, ...
    removenoise, ...
    surfacefirst, ...
    LFPDir, ...
    treeversion, ...
    trackcoordinates);

%% ------------------------------------------------------------------------
% SAVE OUTPUT
%% ------------------------------------------------------------------------

save(fullfile(dataRoot, 'Depth2AreaPerUnit.mat'), 'Depth2AreaPerUnit');

disp('Alignment complete. Output saved to Depth2AreaPerUnit.mat');
