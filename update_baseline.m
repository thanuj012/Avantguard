% ============================================
% Avantguard — Baseline Updater
% update_baseline.m
% Run manually after servicing or monthly
% ============================================

fs           = 2000;
N            = 512;
winSize      = 128;
overlap      = 64;
hop          = winSize - overlap;
f0           = 50;
numHarmonics = 10;
masterFile   = 'avantguard_baselines.csv';
updateWeight = 0.05;   % 5% nudge toward new reading

hannWin  = 0.5 * (1 - cos(2*pi*(0:winSize-1)/(winSize-1)));
freqAxis = [];

% ============================================
% STEP 1 — Load Master File
% ============================================
fprintf('============================================\n');
fprintf('     AVANTGUARD — BASELINE UPDATER          \n');
fprintf('============================================\n\n');

if ~isfile(masterFile)
    error('Master baseline file not found. Run calibrate.m first.');
end

rawTable   = readtable(masterFile, 'VariableNamingRule', 'preserve');
allNames   = rawTable.Device;
allMetrics = rawTable.Metric;
deviceList = unique(allNames, 'stable');
numDevices = length(deviceList);

fprintf('Devices in master file:\n');
for d = 1:numDevices
    meanRow = rawTable(strcmp(allNames, deviceList{d}) & strcmp(allMetrics, 'mean'), :);
    fprintf('  [%d] %-20s | Reliability: %d | Failure prob: %d%%\n', ...
            d, deviceList{d}, meanRow.Reliability_Score, meanRow.Failure_Prob);
end

% ============================================
% STEP 2 — Select Device
% ============================================
fprintf('\nWhich device do you want to update?\n');
choice = input('Enter device number: ');

if choice < 1 || choice > numDevices
    error('Invalid choice.');
end

deviceName = deviceList{choice};
dKey       = matlab.lang.makeValidName(deviceName);
fprintf('\nSelected: %s\n', deviceName);

% ============================================
% STEP 3 — Update Mode
% ============================================
fprintf('\nUpdate mode:\n');
fprintf('  1 → Rolling update (5%% nudge toward new live reading)\n');
fprintf('  2 → Full recalibration (record fresh baseline, replace completely)\n');
fprintf('  3 → Update reliability score only (no new recording needed)\n');
mode = input('Enter choice (1-3): ');

% ============================================
% MODE 3 — Reliability update only
% ============================================
if mode == 3
    fprintf('\nRe-running reliability assessment for %s...\n', deviceName);
    [newReliability, newFailureProb, newGrade] = reliability(deviceName);

    % update mean row in table
    meanIdx = find(strcmp(allNames, deviceName) & strcmp(allMetrics, 'mean'));
    rawTable.Reliability_Score(meanIdx) = newReliability;
    rawTable.Failure_Prob(meanIdx)      = newFailureProb;
    rawTable.Grade(meanIdx)             = {newGrade};

    % save back
    writetable(rawTable, masterFile);

    fprintf('\nReliability updated for %s:\n', deviceName);
    fprintf('  Score : %d / 100\n', newReliability);
    fprintf('  Prob  : %d%%\n', newFailureProb);
    fprintf('  Grade : %s\n', newGrade);
    fprintf('Master file saved.\n');
    return;
end

% ============================================
% STEP 4 — Connect ESP8266 (modes 1 and 2)
% ============================================
fprintf('\nMake sure ONLY %s is connected.\n', deviceName);
fprintf('Press Enter when ready...\n');
pause;

comPort = input('Enter COM port (e.g. COM5): ');
s = serialport(strtrim(comPort), 115200);
s.Timeout = 30;
configureTerminator(s, "LF");
flush(s);

% recording duration
if mode == 1
    recordingTime = 60;   % 1 minute for rolling update
else
    recordingTime = 120;  % 2 minutes for full recalibration
end

fprintf('\nConnected. Recording for %d seconds...\n\n', recordingTime);

% ============================================
% STEP 5 — Record New Data
% ============================================
batchNum  = 0;
startTime = tic;
allHarmonics = [];
allTHD       = [];

while toc(startTime) < recordingTime
    data = zeros(1, N);
    for i = 1:N
        line = readline(s);
        data(i) = str2double(line);
    end
    data = data - mean(data);

    numFrames = floor((N - winSize) / hop) + 1;
    numFreqs  = winSize/2 + 1;
    stftMatrix = zeros(numFreqs, numFrames);

    for frame = 1:numFrames
        startIdx  = (frame-1)*hop + 1;
        segment   = data(startIdx : startIdx+winSize-1);
        windowed  = segment .* hannWin;
        fftResult = fft(windowed, winSize);
        stftMatrix(:, frame) = abs(fftResult(1:numFreqs)) * 2 / winSize;
    end

    if isempty(freqAxis)
        freqAxis = (0:numFreqs-1) * (fs/winSize);
    end

    harmonics = zeros(1, numHarmonics);
    for h = 1:numHarmonics
        targetFreq = h * f0;
        [~, binIdx] = min(abs(freqAxis - targetFreq));
        harmonics(h) = mean(stftMatrix(binIdx, :));
    end

    thd = sqrt(sum(harmonics(2:end).^2)) / harmonics(1) * 100;

    allHarmonics = [allHarmonics; harmonics];
    allTHD       = [allTHD; thd];
    batchNum     = batchNum + 1;

    fprintf('Batch %d | %.1fs / %ds | THD: %.1f%%\n', ...
            batchNum, toc(startTime), recordingTime, thd);
end

clear s;
fprintf('\nRecording complete. %d batches collected.\n\n', batchNum);

% ============================================
% STEP 6 — Compute New Stats
% ============================================
new_mean = mean(allHarmonics, 1);
new_std  = std(allHarmonics, 1);
new_thd  = mean(allTHD);
new_rms  = new_mean(1);

% ============================================
% STEP 7 — Apply Update to Master File
% ============================================

% get old values
meanIdx  = find(strcmp(allNames, deviceName) & strcmp(allMetrics, 'mean'));
stdIdx   = find(strcmp(allNames, deviceName) & strcmp(allMetrics, 'std'));
upperIdx = find(strcmp(allNames, deviceName) & strcmp(allMetrics, 'upper'));
lowerIdx = find(strcmp(allNames, deviceName) & strcmp(allMetrics, 'lower'));

hCols = 3:3+numHarmonics-1;

old_mean = table2array(rawTable(meanIdx, hCols));
old_std  = table2array(rawTable(stdIdx,  hCols));
old_thd  = rawTable.THD(meanIdx);

if mode == 1
    % rolling update — 5% nudge
    updated_mean = (1 - updateWeight) * old_mean + updateWeight * new_mean;
    updated_std  = (1 - updateWeight) * old_std  + updateWeight * new_std;
    updated_thd  = (1 - updateWeight) * old_thd  + updateWeight * new_thd;
    updated_rms  = updated_mean(1);
    modeStr      = 'Rolling update (5%)';
else
    % full replacement
    updated_mean = new_mean;
    updated_std  = new_std;
    updated_thd  = new_thd;
    updated_rms  = new_rms;
    modeStr      = 'Full recalibration';
end

updated_upper = updated_mean + 2*updated_std;
updated_lower = max(0, updated_mean - 2*updated_std);

% write updated rows back to table
for h = 1:numHarmonics
    colName = rawTable.Properties.VariableNames{hCols(h)};
    rawTable.(colName)(meanIdx)  = updated_mean(h);
    rawTable.(colName)(stdIdx)   = updated_std(h);
    rawTable.(colName)(upperIdx) = updated_upper(h);
    rawTable.(colName)(lowerIdx) = updated_lower(h);
end

rawTable.THD(meanIdx)         = updated_thd;
rawTable.RMS_current(meanIdx) = updated_rms;

writetable(rawTable, masterFile);

% ============================================
% STEP 8 — Summary
% ============================================
fprintf('============================================\n');
fprintf('         BASELINE UPDATE COMPLETE           \n');
fprintf('============================================\n');
fprintf('Device      : %s\n', deviceName);
fprintf('Mode        : %s\n', modeStr);
fprintf('Batches     : %d\n', batchNum);
fprintf('--------------------------------------------\n');
fprintf('             OLD        NEW\n');
fprintf('THD:         %.2f%%     %.2f%%\n', old_thd, updated_thd);
fprintf('H1:          %.4f     %.4f\n', old_mean(1), updated_mean(1));
fprintf('H3:          %.4f     %.4f\n', old_mean(3), updated_mean(3));
fprintf('H5:          %.4f     %.4f\n', old_mean(5), updated_mean(5));
fprintf('--------------------------------------------\n');
fprintf('Master file saved: %s\n', masterFile);
fprintf('============================================\n');