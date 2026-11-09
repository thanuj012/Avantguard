% ============================================
% Avantguard — Reliability Scoring
% reliability.m
% Called by calibrate.m — do not run directly
% ============================================

function [reliabilityScore, failureProb, reliabilityGrade] = reliability(deviceType)

fprintf('\n========== RELIABILITY ASSESSMENT ==========\n');
fprintf('Device type: %s\n\n', deviceType);

score = 100;  % start full, deduct based on answers

% ---- Factor 1: Age ----
fprintf('1. How old is this device?\n');
fprintf('   1 → Less than 1 year\n');
fprintf('   2 → 1 to 3 years\n');
fprintf('   3 → 3 to 7 years\n');
fprintf('   4 → More than 7 years\n');
age = input('   Enter choice (1-4): ');

switch age
    case 1, agePenalty = 0;
    case 2, agePenalty = 5;
    case 3, agePenalty = 15;
    case 4, agePenalty = 30;
    otherwise, agePenalty = 10;
end

% ---- Factor 2: Daily usage ----
fprintf('\n2. How many hours per day is it used?\n');
fprintf('   1 → Less than 2 hours\n');
fprintf('   2 → 2 to 6 hours\n');
fprintf('   3 → 6 to 12 hours\n');
fprintf('   4 → More than 12 hours (always on)\n');
usage = input('   Enter choice (1-4): ');

switch usage
    case 1, usagePenalty = 0;
    case 2, usagePenalty = 5;
    case 3, usagePenalty = 10;
    case 4, usagePenalty = 20;
    otherwise, usagePenalty = 5;
end

% ---- Factor 3: Last service / maintenance ----
fprintf('\n3. When was it last serviced or checked?\n');
fprintf('   1 → Never serviced\n');
fprintf('   2 → More than 2 years ago\n');
fprintf('   3 → 1 to 2 years ago\n');
fprintf('   4 → Less than 1 year ago\n');
service = input('   Enter choice (1-4): ');

switch service
    case 1, servicePenalty = 25;
    case 2, servicePenalty = 15;
    case 3, servicePenalty = 8;
    case 4, servicePenalty = 0;
    otherwise, servicePenalty = 15;
end

% ---- Factor 4: Visible/audible symptoms ----
fprintf('\n4. Any visible or audible symptoms?\n');
fprintf('   1 → None, working normally\n');
fprintf('   2 → Slight noise or vibration\n');
fprintf('   3 → Flickering / dimming / intermittent\n');
fprintf('   4 → Burning smell / excessive heat\n');
fprintf('   5 → Multiple symptoms\n');
symptom = input('   Enter choice (1-5): ');

switch symptom
    case 1, symptomPenalty = 0;
    case 2, symptomPenalty = 15;
    case 3, symptomPenalty = 20;
    case 4, symptomPenalty = 35;
    case 5, symptomPenalty = 45;
    otherwise, symptomPenalty = 0;
end

% ---- Factor 5: Voltage condition ----
fprintf('\n5. Voltage supply condition?\n');
fprintf('   1 → Stable, within rated range\n');
fprintf('   2 → Occasional fluctuations\n');
fprintf('   3 → Frequent fluctuations / voltage spikes\n');
voltage = input('   Enter choice (1-3): ');

switch voltage
    case 1, voltagePenalty = 0;
    case 2, voltagePenalty = 8;
    case 3, voltagePenalty = 18;
    otherwise, voltagePenalty = 5;
end

% ---- Factor 6: Device type base penalty ----
% some devices are inherently more failure-prone
switch lower(deviceType)
    case 'motor',       typePenalty = 10;  % mechanical wear
    case 'ceiling_fan', typePenalty = 8;   % capacitor + bearing
    case 'compressor',  typePenalty = 12;  % high stress
    case 'led_bulb',    typePenalty = 5;   % driver cap aging
    case 'cfl',         typePenalty = 6;   % ballast aging
    case 'refrigerator',typePenalty = 10;  % compressor + motor
    case 'iron',        typePenalty = 2;   % resistive, simple
    case 'heater',      typePenalty = 2;   % resistive, simple
    otherwise,          typePenalty = 5;   % unknown, moderate
end

% ---- Compute final score ----
totalPenalty = agePenalty + usagePenalty + servicePenalty + ...
               symptomPenalty + voltagePenalty + typePenalty;

reliabilityScore = max(0, score - totalPenalty);
failureProb      = 100 - reliabilityScore;

% ---- Grade ----
if reliabilityScore >= 80
    reliabilityGrade = 'A — Low Risk';
elseif reliabilityScore >= 60
    reliabilityGrade = 'B — Moderate Risk';
elseif reliabilityScore >= 40
    reliabilityGrade = 'C — High Risk';
else
    reliabilityGrade = 'D — Critical Risk';
end

% ---- Breakdown display ----
fprintf('\n---------- Scoring Breakdown ----------\n');
fprintf('Device type penalty  : -%d\n', typePenalty);
fprintf('Age penalty          : -%d\n', agePenalty);
fprintf('Usage penalty        : -%d\n', usagePenalty);
fprintf('Service penalty      : -%d\n', servicePenalty);
fprintf('Symptom penalty      : -%d\n', symptomPenalty);
fprintf('Voltage penalty      : -%d\n', voltagePenalty);
fprintf('---------------------------------------\n');
fprintf('Total penalty        : -%d\n', totalPenalty);
fprintf('Reliability score    : %d / 100\n', reliabilityScore);
fprintf('Failure probability  : %d%%\n', failureProb);
fprintf('Grade                : %s\n', reliabilityGrade);
fprintf('=======================================\n\n');

end