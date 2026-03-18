%% Load data
clear; clc;

neuralData = load("C:\Users\Data Analysis\Desktop\ephysExercise\neuralData.mat");
behavioralData = load("C:\Users\Data Analysis\Desktop\ephysExercise\behaviorData.mat");

FR = neuralData.FR;   % expected size: [nCells x nFrames]
[nCells, nFrames] = size(FR);

% Handle either variable name
if isfield(behavioralData, 'behaviorData')
    behTable = behavioralData.behaviorData;
elseif isfield(behavioralData, 'behaviorCell')
    behTable = behavioralData.behaviorCell;
else
    error('Could not find behaviorData or behaviorCell in behaviorData.mat');
end

%% Parameters
fs = 50;                    % Hz
preTime = 1;                % seconds before onset
postTime = 3;               % seconds after onset
preFrames = round(preTime * fs);
postFrames = round(postTime * fs);

t = (-preFrames:postFrames) / fs;
nWin = numel(t);

nBehaviors = size(behTable, 1);

%% Z-score each neuron across whole recording
FRz = zscore(FR, 0, 2);

%% Output folder
outFolder = "C:\Users\Data Analysis\Desktop\ephysExercise\bout_heatmaps_PCsorted";
if ~exist(outFolder, 'dir')
    mkdir(outFolder);
end

%% Loop through behaviors
for b = 1:nBehaviors
    behaviorName = behTable{b,1};
    behVec = behTable{b,2};
    behVec = behVec(:)';

    % Find onset frames: 0 -> 1 transitions
    onsets = find(diff([0 behVec]) == 1);

    % Discard onsets too close to edges
    validOnsets = onsets(onsets > preFrames & onsets <= (nFrames - postFrames));
    nBouts = numel(validOnsets);

    if nBouts == 0
        fprintf('No valid bouts found for %s\n', behaviorName);
        continue
    end

    % Behavior-specific subfolder
    behFolder = fullfile(outFolder, behaviorName);
    if ~exist(behFolder, 'dir')
        mkdir(behFolder);
    end

    %% Plot each bout individually
    for k = 1:nBouts
        idx = (validOnsets(k)-preFrames):(validOnsets(k)+postFrames);
        boutMat = FRz(:, idx);   % [neurons x time]

        % PCA-based sorting of neurons for this single bout
        [~, score, ~] = pca(boutMat);
        sortMetric = score(:,1);
        [~, sortOrder] = sort(sortMetric, 'descend');

        boutMatSorted = boutMat(sortOrder, :);

        % Robust color scaling
        lim = prctile(abs(boutMatSorted(:)), 98);
        if lim == 0 || isnan(lim)
            lim = 1;
        end

        % Create figure
        f = figure('Visible','off', 'Color','w', 'Position', [100 100 900 700]);
        imagesc(t, 1:nCells, boutMatSorted);
        axis tight;
        clim([-lim lim]);   % <-- actually applies the color limits
        xlabel('Time from onset (s)');
        ylabel('Neuron (sorted by PC1)');
        title(sprintf('%s | Bout %d/%d | Onset frame %d', ...
            behaviorName, k, nBouts, validOnsets(k)), ...
            'Interpreter', 'none');
        xline(0, 'w--', 'LineWidth', 1.5);
        colorbar;
        colormap(parula);

        % Save
        saveas(f, fullfile(behFolder, sprintf('%s_bout_%03d_PC1sorted.png', behaviorName, k)));
        savefig(f, fullfile(behFolder, sprintf('%s_bout_%03d_PC1sorted.fig', behaviorName, k)));
        close(f);
    end
    fprintf('Saved %d bout plots for %s\n', nBouts, behaviorName);
end

disp('Done.')

%%

%% Load data
clear; clc;

neuralData = load("C:\Users\Data Analysis\Desktop\ephysExercise\neuralData.mat");
behavioralData = load("C:\Users\Data Analysis\Desktop\ephysExercise\behaviorData.mat");

FR = neuralData.FR;   % expected size: [nCells x nFrames]
[nCells, nFrames] = size(FR);

% Handle either variable name
if isfield(behavioralData, 'behaviorData')
    behTable = behavioralData.behaviorData;
elseif isfield(behavioralData, 'behaviorCell')
    behTable = behavioralData.behaviorCell;
else
    error('Could not find behaviorData or behaviorCell in behaviorData.mat');
end

%% Parameters
fs = 50;                    % Hz
preTime = 1;                % seconds before onset
postTime = 3;               % seconds after onset
preFrames = round(preTime * fs);
postFrames = round(postTime * fs);

t = (-preFrames:postFrames) / fs;
nWin = numel(t);

%% Z-score each neuron across whole recording
FRz = zscore(FR, 0, 2);

%% Combine Left/Right by pooling onsets, NOT by OR-ing vectors
origNames = behTable(:,1);
origVecs  = behTable(:,2);

baseNames = cell(size(origNames));

for i = 1:numel(origNames)
    thisName = origNames{i};
    baseNames{i} = regexprep(thisName, '(Left|Right)$', '');
end

[uniqueBaseNames, ~, groupIdx] = unique(baseNames, 'stable');

combinedBehTable = cell(numel(uniqueBaseNames), 3);
% col 1 = combined behavior name
% col 2 = combined onset list
% col 3 = source labels for each onset (optional)

for g = 1:numel(uniqueBaseNames)
    combinedName = uniqueBaseNames{g};
    memberIdx = find(groupIdx == g);

    allOnsets = [];
    allSources = {};

    for j = 1:numel(memberIdx)
        thisName = origNames{memberIdx(j)};
        thisVec = origVecs{memberIdx(j)};
        thisVec = thisVec(:)';

        % Force length match
        if numel(thisVec) < nFrames
            thisVec(end+1:nFrames) = 0;
        elseif numel(thisVec) > nFrames
            thisVec = thisVec(1:nFrames);
        end

        % Get onsets from this specific Left/Right behavior
        thisOnsets = find(diff([0 thisVec]) == 1);

        allOnsets = [allOnsets, thisOnsets];
        allSources = [allSources, repmat({thisName}, 1, numel(thisOnsets))];
    end

    % Sort all onsets together, preserving overlaps as separate bouts
    [allOnsetsSorted, sortIdx] = sort(allOnsets);
    allSourcesSorted = allSources(sortIdx);

    combinedBehTable{g,1} = combinedName;
    combinedBehTable{g,2} = allOnsetsSorted;
    combinedBehTable{g,3} = allSourcesSorted;
end

nBehaviors = size(combinedBehTable, 1);

%% Output folder
outFolder = "C:\Users\Data Analysis\Desktop\ephysExercise\bout_heatmaps_PCsorted_combinedLR";
if ~exist(outFolder, 'dir')
    mkdir(outFolder);
end

%% Loop through combined behaviors
for b = 1:nBehaviors
    behaviorName = combinedBehTable{b,1};
    allOnsets = combinedBehTable{b,2};
    allSources = combinedBehTable{b,3};

    % Discard onsets too close to edges
    validMask = allOnsets > preFrames & allOnsets <= (nFrames - postFrames);
    validOnsets = allOnsets(validMask);
    validSources = allSources(validMask);

    nBouts = numel(validOnsets);

    if nBouts == 0
        fprintf('No valid bouts found for %s\n', behaviorName);
        continue
    end

    % Behavior-specific subfolder
    behFolder = fullfile(outFolder, behaviorName);
    if ~exist(behFolder, 'dir')
        mkdir(behFolder);
    end

    %% Plot each bout individually
    for k = 1:nBouts
        idx = (validOnsets(k)-preFrames):(validOnsets(k)+postFrames);
        boutMat = FRz(:, idx);   % [neurons x time]

        % PCA-based sorting of neurons for this single bout
        [~, score, ~] = pca(boutMat);
        [~, sortOrder] = sort(score(:,1), 'descend');

        boutMatSorted = boutMat(sortOrder, :);

        % Create figure
        f = figure('Visible','off', 'Color','w', 'Position', [100 100 900 700]);
        imagesc(t, 1:nCells, boutMatSorted);
        axis tight;
        clim([-2 2]);
        xlabel('Time from onset (s)');
        ylabel('Neuron (sorted by PC1)');
        title(sprintf('%s | Bout %d/%d | Onset frame %d | Source: %s', ...
            behaviorName, k, nBouts, validOnsets(k), validSources{k}), ...
            'Interpreter', 'none');
        xline(0, 'w--', 'LineWidth', 1.5);
        colorbar;
        colormap(parula);

        % Save
        saveas(f, fullfile(behFolder, sprintf('%s_bout_%03d_PC1sorted.png', behaviorName, k)));
        savefig(f, fullfile(behFolder, sprintf('%s_bout_%03d_PC1sorted.fig', behaviorName, k)));
        close(f);
    end

    fprintf('Saved %d combined bout plots for %s\n', nBouts, behaviorName);
end

disp('Done.')


%% Split submissionSignFromInt into nearAttack vs farFromAttack
% Rule:
% farFromAttack = no attack frames within 5 s before submission onset
%                 and no attack frames within 5 s after submission offset
% nearAttack    = at least one attack frame in that expanded window

bufferSec = 5;
bufferFrames = round(bufferSec * fs);

% --- get combined attack and submission vectors from original behaviors ---
attackVec = zeros(1, nFrames);
submissionVec = zeros(1, nFrames);

for i = 1:size(behTable,1)
    thisName = behTable{i,1};
    thisVec  = behTable{i,2};
    thisVec  = thisVec(:)';

    % force length match
    if numel(thisVec) < nFrames
        thisVec(end+1:nFrames) = 0;
    elseif numel(thisVec) > nFrames
        thisVec = thisVec(1:nFrames);
    end

    baseName = regexprep(thisName, '(Left|Right)$', '');

    if strcmp(baseName, 'attackOfInt')
        attackVec = attackVec | logical(thisVec);
    elseif strcmp(baseName, 'submissionSignFromInt')
        submissionVec = submissionVec | logical(thisVec);
    end
end

attackVec = double(attackVec);
submissionVec = double(submissionVec);

% --- find submission bout onsets and offsets from combined submission vector ---
submissionStarts = find(diff([0 submissionVec]) == 1);
submissionStops  = find(diff([submissionVec 0]) == -1);

if numel(submissionStarts) ~= numel(submissionStops)
    error('Mismatch between submission starts and stops.');
end

% --- classify each submission bout ---
nearVec = zeros(1, nFrames);
farVec  = zeros(1, nFrames);

submissionClassTable = cell(numel(submissionStarts), 5);
% cols:
% 1 start
% 2 stop
% 3 expanded start
% 4 expanded stop
% 5 class ('nearAttack' or 'farFromAttack')

for i = 1:numel(submissionStarts)
    s = submissionStarts(i);
    e = submissionStops(i);

    sCheck = max(1, s - bufferFrames);
    eCheck = min(nFrames, e + bufferFrames);

    hasAttackNearby = any(attackVec(sCheck:eCheck) > 0);

    if hasAttackNearby
        nearVec(s:e) = 1;
        thisClass = 'nearAttack';
    else
        farVec(s:e) = 1;
        thisClass = 'farFromAttack';
    end

    submissionClassTable{i,1} = s;
    submissionClassTable{i,2} = e;
    submissionClassTable{i,3} = sCheck;
    submissionClassTable{i,4} = eCheck;
    submissionClassTable{i,5} = thisClass;
end

fprintf('Submission bouts near attack: %d\n', sum(strcmp(submissionClassTable(:,5), 'nearAttack')));
fprintf('Submission bouts far from attack: %d\n', sum(strcmp(submissionClassTable(:,5), 'farFromAttack')));

%% Build a new behavior table with split submission behaviors
plotBehTable = combinedBehTable;

% remove original submissionSignFromInt entry if present
keepMask = true(size(plotBehTable,1),1);
for i = 1:size(plotBehTable,1)
    if strcmp(plotBehTable{i,1}, 'submissionSignFromInt')
        keepMask(i) = false;
    end
end
plotBehTable = plotBehTable(keepMask,:);

% add the two new submission behaviors
plotBehTable(end+1,:) = {'submissionSignFromInt_nearAttack', double(nearVec), []};
plotBehTable(end+1,:) = {'submissionSignFromInt_farFromAttack', double(farVec), []};

nBehaviors = size(plotBehTable, 1);

%% Loop through behaviors
for b = 1:nBehaviors
    behaviorName = plotBehTable{b,1};

    % Support either pooled-onset behaviors or binary-vector behaviors
    if isnumeric(plotBehTable{b,2}) && numel(plotBehTable{b,2}) == nFrames
        behVec = plotBehTable{b,2};
        behVec = behVec(:)';
        allOnsets = find(diff([0 behVec]) == 1);
        allSources = repmat({behaviorName}, 1, numel(allOnsets));
    else
        allOnsets = plotBehTable{b,2};
        allSources = plotBehTable{b,3};
    end

    % Discard onsets too close to edges
    validMask = allOnsets > preFrames & allOnsets <= (nFrames - postFrames);
    validOnsets = allOnsets(validMask);
    validSources = allSources(validMask);

    nBouts = numel(validOnsets);

    if nBouts == 0
        fprintf('No valid bouts found for %s\n', behaviorName);
        continue
    end

    behFolder = fullfile(outFolder, behaviorName);
    if ~exist(behFolder, 'dir')
        mkdir(behFolder);
    end

    for k = 1:nBouts
        idx = (validOnsets(k)-preFrames):(validOnsets(k)+postFrames);
        boutMat = FRz(:, idx);

        [~, score, ~] = pca(boutMat);
        [~, sortOrder] = sort(score(:,1), 'descend');
        boutMatSorted = boutMat(sortOrder, :);

        f = figure('Visible','off', 'Color','w', 'Position', [100 100 900 700]);
        imagesc(t, 1:nCells, boutMatSorted);
        axis tight;
        clim([-2 2]);
        xlabel('Time from onset (s)');
        ylabel('Neuron (sorted by PC1)');
        title(sprintf('%s | Bout %d/%d | Onset frame %d', ...
            behaviorName, k, nBouts, validOnsets(k)), ...
            'Interpreter', 'none');
        xline(0, 'w--', 'LineWidth', 1.5);
        colorbar;
        colormap(parula);

        saveas(f, fullfile(behFolder, sprintf('%s_bout_%03d_PC1sorted.png', behaviorName, k)));
        savefig(f, fullfile(behFolder, sprintf('%s_bout_%03d_PC1sorted.fig', behaviorName, k)));
        close(f);
    end

    fprintf('Saved %d bout plots for %s\n', nBouts, behaviorName);
end