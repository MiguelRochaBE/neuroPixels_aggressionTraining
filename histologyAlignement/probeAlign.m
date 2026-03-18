%% USER PATHS
dataRoot = 'J:\project_trainingAggression\Data\20250817_mouse975826\Day01\neuralData\catgt_20250817_m975826_obs1_g0\20250817_m975826_obs1_g0_imec0\Kilosort4_probe0\sorter_output';
histologyExport = 'J:\project_trainingAggression\histologyData\975826_Agg1\herbsProbeTrajectory\probes';

% Kilosort output root (contains params.py + all .npy)
ksRoot = dataRoot;

% Curation folder (contains cluster_info.tsv / cluster_group.tsv)
curationDir = fullfile(ksRoot, 'autoForNeuroConcat');

AllenCCFPath = 'J:\project_trainingAggression\Code\Neurpixels_aggressionTraining\histologyAlignement\allenCCF-master';

%% PATHS (edit these to where you cloned them)
addpath(genpath(AllenCCFPath));
addpath(genpath('spikes-master'));            % <-- CHANGE to your actual spikes-master location
addpath(genpath('npy-matlab-master'));
addpath(genpath('neuropixel-utils-master'));

%% OPTIONS
removenoise  = 1;
surfacefirst = 0;
treeversion  = 2;
LFPDir       = []; % unused

%% REQUIRED: sp must already be loaded
% (Your script assumes sp exists with fields like sp.st, sp.clu, etc.)
assert(exist('sp','var')==1 && isstruct(sp), 'sp not found. Load your Kilosort/spikes struct into variable "sp" first.');
assert(isfield(sp,'st') && isfield(sp,'clu'), 'sp must contain at least sp.st and sp.clu.');

% alignatlasdata expects sp.RecSes to exist
if ~isfield(sp,'RecSes') || isempty(sp.RecSes)
    sp.RecSes = ones(size(sp.st));  % one recording/session for all spikes
end

% Ensure per-spike depths exist (from Kilosort)
if ~isfield(sp,'spikeDepths') || isempty(sp.spikeDepths)
    posFile = fullfile(ksRoot,'spike_positions.npy');
    assert(exist(posFile,'file')==2, 'Missing %s (needed to build sp.spikeDepths)', posFile);
    spikePos = readNPY(posFile);               % [nSpikes x 2]
    sp.spikeDepths = spikePos(:,2);            % y = depth along probe (um)
end

assert(numel(sp.spikeDepths) == numel(sp.st), ...
    'sp.spikeDepths length (%d) != sp.st length (%d)', numel(sp.spikeDepths), numel(sp.st));

%% LOAD CURATED CLUSTER INFO (Phy)
clusinfo = struct();

cluster_info_file  = fullfile(curationDir, 'cluster_info.tsv');
cluster_group_file = fullfile(curationDir, 'cluster_group.tsv'); % sometimes named this

if exist(cluster_info_file,'file')
    T = readtable(cluster_info_file, 'FileType','text', 'Delimiter','\t');

    % cluster_id
    assert(any(strcmpi(T.Properties.VariableNames,'cluster_id')), ...
        'cluster_info.tsv missing cluster_id column');
    clusinfo.cluster_id = T.cluster_id;

    % depth
    if any(strcmpi(T.Properties.VariableNames,'depth'))
        clusinfo.depth = T.depth;
    elseif any(strcmpi(T.Properties.VariableNames,'depth_um'))
        clusinfo.depth = T.depth_um;
    elseif isfield(sp,'clusterDepths') && numel(sp.clusterDepths)==height(T)
        warning('No depth column in cluster_info.tsv; using sp.clusterDepths (same length as cluster_info)');
        clusinfo.depth = sp.clusterDepths;
    else
        error('No depth/depth_um in cluster_info.tsv and cannot safely fall back to sp.clusterDepths');
    end

    % channel
    if any(strcmpi(T.Properties.VariableNames,'ch'))
        clusinfo.ch = T.ch;
    elseif any(strcmpi(T.Properties.VariableNames,'channel'))
        clusinfo.ch = T.channel;
    elseif isfield(sp,'clusterChannels') && numel(sp.clusterChannels)==height(T)
        warning('No ch/channel column in cluster_info.tsv; using sp.clusterChannels (same length as cluster_info)');
        clusinfo.ch = sp.clusterChannels;
    else
        error('No ch/channel in cluster_info.tsv and cannot safely fall back to sp.clusterChannels');
    end

    % ---- GROUP (the juice): prefer TSV "group" ----
    if any(strcmpi(T.Properties.VariableNames,'group'))
        clusinfo.group = cellstr(strtrim(string(T.group)));      % 'good','mua','noise'
    elseif any(strcmpi(T.Properties.VariableNames,'KSLabel'))
        clusinfo.group = cellstr(strtrim(string(T.KSLabel)));
    elseif exist(cluster_group_file,'file')
        G = readtable(cluster_group_file, 'FileType','text', 'Delimiter','\t');
        if any(strcmpi(G.Properties.VariableNames,'cluster_id')) && any(strcmpi(G.Properties.VariableNames,'group'))
            [tf,loc] = ismember(clusinfo.cluster_id, G.cluster_id);
            lab = repmat({'unsorted'}, numel(clusinfo.cluster_id), 1);
            lab(tf) = cellstr(strtrim(string(G.group(loc(tf)))));
            clusinfo.group = lab;
            warning('Using labels from cluster_group.tsv');
        else
            clusinfo.group = repmat({'unsorted'}, height(T), 1);
            warning('cluster_group.tsv exists but missing required columns; marking all as unsorted');
        end
    else
        clusinfo.group = repmat({'unsorted'}, height(T), 1);
        warning('No group/KSLabel in cluster_info.tsv; no cluster_group.tsv; marking all as unsorted');
    end

    % Keep KSLabel too (compatibility with other code)
    clusinfo.KSLabel = clusinfo.group;

    % ---- numeric cgs (2=good, 1=mua/unsorted, 0=noise) ----
    g = lower(string(clusinfo.group));
    cgs = ones(numel(g),1);         % default = mua/unsorted
    cgs(g=="good")     = 2;
    cgs(g=="mua")      = 1;
    cgs(g=="noise")    = 0;
    cgs(g=="unsorted") = 1;
    clusinfo.cgs = cgs;

    % shank id (optional; default 1)
    if any(strcmpi(T.Properties.VariableNames,'shank'))
        clusinfo.ShankID = T.shank;
    else
        clusinfo.ShankID = ones(height(T),1);
    end

    % recording session id: alignatlasdata expects this field exists
    clusinfo.RecSesID = ones(height(T),1);

else
    warning('cluster_info.tsv not found in %s; using minimal clusinfo from sp', curationDir);

    clusinfo.cluster_id = unique(sp.clu);

    assert(isfield(sp,'clusterDepths') && isfield(sp,'clusterChannels'), ...
        'Fallback requires sp.clusterDepths and sp.clusterChannels');

    clusinfo.depth = sp.clusterDepths;
    clusinfo.ch    = sp.clusterChannels;

    % default everything to "good" in fallback
    clusinfo.group  = repmat({'good'}, numel(clusinfo.cluster_id), 1);
    clusinfo.KSLabel = clusinfo.group;

    g = lower(string(clusinfo.group));
    clusinfo.cgs = 2*ones(numel(g),1);  % all good

    clusinfo.ShankID  = ones(numel(clusinfo.cluster_id),1);
    clusinfo.RecSesID = ones(numel(clusinfo.cluster_id),1);
end

% Optional sanity check: show counts
% disp(tabulate(categorical(clusinfo.group)))

%% LOAD HISTOLOGY EXPORTS (Python output from HERBS probe.pkl)
csvFiles = dir(fullfile(histologyExport,'histology_shank*.csv'));
if isempty(csvFiles)
    error('No histology_shank*.csv found in %s', histologyExport);
end

% Sort shanks by number
shNums = nan(numel(csvFiles),1);
for i = 1:numel(csvFiles)
    tok = regexp(csvFiles(i).name,'histology_shank(\d+)\.csv','tokens','once');
    shNums(i) = str2double(tok{1});
end
[~,ord] = sort(shNums);
csvFiles = csvFiles(ord);
shNums   = shNums(ord);

histinfo        = cell(numel(csvFiles),1);
trackcoordinates = cell(numel(csvFiles),1);

for i = 1:numel(csvFiles)
    sh = shNums(i);

    histinfo{i} = readtable(fullfile(csvFiles(i).folder, csvFiles(i).name));

    % Sanity checks
    if ~any(strcmp(histinfo{i}.Properties.VariableNames,'Position')) || ...
       ~any(strcmp(histinfo{i}.Properties.VariableNames,'RegionAcronym'))
        error('histology_shank%d.csv must contain columns: Position, RegionAcronym', sh);
    end

    npyFile = fullfile(histologyExport, sprintf('trackcoordinates_shank%d.npy', sh));
    if exist(npyFile,'file')
        trackcoordinates{i} = readNPY(npyFile);
    else
        warning('Missing %s. Running without coordinates for shank %d (still possible).', npyFile, sh);
        trackcoordinates{i} = [];
    end
end

% If only one shank, pass single table/array (then re-wrap as cell for alignatlasdata signature)
if numel(histinfo) == 1
    histinfo = {histinfo{1}};
    trackcoordinates = {trackcoordinates{1}};
end

%% RUN ALIGNMENT
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

%% SAVE
save(fullfile(dataRoot,'Depth2AreaPerUnit.mat'), 'Depth2AreaPerUnit');
writetable(Depth2AreaPerUnit, fullfile(dataRoot,'Depth2AreaPerUnit.csv'));

disp('Alignment complete: Depth2AreaPerUnit.mat and .csv saved.');
