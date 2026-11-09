% ============================================
% Avantguard — Device Calibration
% calibrate.m
% Run this once per device
% ============================================

fs           = 2000;
N            = 512;
winSize      = 128;
overlap      = 64;
hop          = winSize - overlap;
f0           = 50;
numHarmonics = 10;
recordingTime = 120;   % seconds

hannWin    = 0.5 * (1 - cos(2*pi*(0:winSize-1)/(winSize-1)));
masterFile = 'avantguard_baselines.csv';

% ============================================
% STEP 1 — Device Info
% ============================================
fprintf('============================================\n');
fprintf('       AVANTGUARD — DEVICE CALIBRATION      \n');
fprintf('============================================\n\n');

deviceName = input('Enter device name (e.g. led_bulb, ceiling_fan, motor): ', 's');
deviceName = strtrim(deviceName);
deviceName = strrep(deviceName, ' ', '_');

rawFile = ['raw_' deviceName '.csv'];

fprintf('\nDevice    : %s\n', deviceName);
fprintf('Raw file  : %s\n', rawFile);
fprintf('Master    : %s\n\n', masterFile);

% ============================================
% STEP 2 — Reliability Assessment
% ============================================
[reliabilityScore, failureProb, reliabilityGrade] = reliability(deviceName);

% ============================================
% STEP 3 — Hardware Connection
% ============================================
fprintf('Make sure ONLY %s is connected to the circuit.\n', deviceName);
fprintf('Press Enter when ready to start recording...\n');
pause;

comPort = input('Enter COM port (e.g. COM5): ', 's');
s = serialport(strtrim(comPort), 115200);
s.Timeout = 30;
configureTerminator(s, "LF");
flush(s);

fprintf('\nConnected to %s\n', strtrim(comPort));
fprintf('Recording for %d seconds...\n\n', recordingTime);

% ============================================
% STEP 4 — Raw Data Recording
% ============================================
rawID = fopen(rawFile, 'w');
fprintf(rawID, 'Batch,Time');
for h = 1:numHarmonics
    fprintf(rawID, ',H%d_%dHz', h, h*f0);
end
fprintf(rawID, ',THD\n');

batchNum  = 0;
startTime = tic;
freqAxis  = [];

while toc(startTime) < recordingTime

    % collect samples
    data = zeros(1, N);
    for i = 1:N
        line = readline(s);
        data(i) = str2double(line);
    end

    % remove DC
    data = data - mean(data);

    % STFT
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

    % frequency axis (computed once)
    if isempty(freqAxis)
        freqAxis = (0:numFreqs-1) * (fs/winSize);
    end

    % extract harmonics
    harmonics = zeros(1, numHarmonics);
    for h = 1:numHarmonics
        targetFreq = h * f0;
        [~, binIdx] = min(abs(freqAxis - targetFreq));
        harmonics(h) = mean(stftMatrix(binIdx, :));
    end

    % THD
    thd = sqrt(sum(harmonics(2:end).^2)) / harmonics(1) * 100;

    % write raw row
    batchNum = batchNum + 1;
    elapsed  = toc(startTime);
    fprintf(rawID, '%d,%.2f', batchNum, elapsed);
    for h = 1:numHarmonics
        fprintf(rawID, ',%.4f', harmonics(h));
    end
    fprintf(rawID, ',%.2f\n', thd);

    % progress
    fprintf('Batch %d | %.1fs / %ds | THD: %.1f%%\n', ...
            batchNum, elapsed, recordingTime, thd);
end

fclose(rawID);
fprintf('\nRecording complete. %d batches saved to %s\n\n', batchNum, rawFile);

% ============================================
% STEP 5 — Compute Baseline Statistics
% ============================================
fprintf('Computing baseline statistics...\n');

rawData = readmatrix(rawFile);
rawData = rawData(2:end, :);
rawData = rawData(~any(isnan(rawData), 2), :);

harmonicCols = rawData(:, 3:3+numHarmonics-1);
thdCol       = rawData(:, 3+numHarmonics);

b_mean = mean(harmonicCols, 1);
b_std  = std(harmonicCols, 1);
b_thd  = mean(thdCol);
b_rms  = b_mean(1);

% ============================================
% STEP 6 — Write to Master Baseline File
% ============================================
if ~isfile(masterFile)
    masterID = fopen(masterFile, 'w');
    fprintf(masterID, 'Device,Metric');
    for h = 1:numHarmonics
        fprintf(masterID, ',H%d_%dHz', h, h*f0);
    end
    fprintf(masterID, ',THD,RMS_current,Reliability_Score,Failure_Prob,Grade\n');
    fclose(masterID);
    fprintf('Created master file: %s\n', masterFile);
else
    fprintf('Appending to master file: %s\n', masterFile);
end

masterID = fopen(masterFile, 'a');

% mean row — has reliability info
fprintf(masterID, '%s,mean', deviceName);
for h = 1:numHarmonics
    fprintf(masterID, ',%.4f', b_mean(h));
end
fprintf(masterID, ',%.2f,%.4f,%d,%d,%s\n', ...
        b_thd, b_rms, reliabilityScore, failureProb, reliabilityGrade);

% std row
fprintf(masterID, '%s,std', deviceName);
for h = 1:numHarmonics
    fprintf(masterID, ',%.4f', b_std(h));
end
fprintf(masterID, ',%.2f,%.4f,,,\n', std(thdCol), std(harmonicCols(:,1)));

% upper bound (mean + 2*std)
fprintf(masterID, '%s,upper', deviceName);
for h = 1:numHarmonics
    fprintf(masterID, ',%.4f', b_mean(h) + 2*b_std(h));
end
fprintf(masterID, ',%.2f,,,\n', b_thd + 2*std(thdCol));

% lower bound (mean - 2*std)
fprintf(masterID, '%s,lower', deviceName);
for h = 1:numHarmonics
    fprintf(masterID, ',%.4f', max(0, b_mean(h) - 2*b_std(h)));
end
fprintf(masterID, ',%.2f,,,\n', max(0, b_thd - 2*std(thdCol)));

fclose(masterID);

% ============================================
% STEP 7 — Final Summary
% ============================================
fprintf('\n============================================\n');
fprintf('         CALIBRATION COMPLETE               \n');
fprintf('============================================\n');
fprintf('Device             : %s\n', deviceName);
fprintf('Batches recorded   : %d\n', batchNum);
fprintf('Baseline THD       : %.2f%%\n', b_thd);
fprintf('RMS current        : %.4f\n', b_rms);
fprintf('Reliability score  : %d / 100\n', reliabilityScore);
fprintf('Failure probability: %d%%\n', failureProb);
fprintf('Grade              : %s\n', reliabilityGrade);
fprintf('--------------------------------------------\n');
fprintf('Raw data saved     : %s\n', rawFile);
fprintf('Master updated     : %s\n', masterFile);
fprintf('============================================\n');

clear s;