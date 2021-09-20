clear all;  clc
% DAVI ROCHA CARVALHO APRIL/2021 - Eng. Acustica @UFSM 
% Test binaural rendering using webcam head tracker 

% MATLAB R2020a
%% Carregar HRTFs
ARIDataset = load('ReferenceHRTF.mat'); 
% separar HRTFs
hrtfData = double(ARIDataset.hrtfData);
hrtfData = permute(hrtfData,[2,3,1]);
% Separar posições de fonte
sourcePosition = ARIDataset.sourcePosition(:,[1,2]);
sourcePosition(:,1) = -(sourcePosition(:,1) - 180);


%% Carregar audio mono
[heli,originalSampleRate] = audioread('Heli_16ch_ACN_SN3D.wav'); % ja vem com o matlab 
heli = 12*heli(:,1); % keep only one channel

sampleRate = 48e3;
heli = resample(heli,sampleRate,originalSampleRate);


%% Jogar audio para objeto DSP
sigsrc = dsp.SignalSource(heli, ...
    'SamplesPerFrame',256, ...
    'SignalEndAction','Cyclic repetition');

% Configurar dispositivo de audio
deviceWriter = audioDeviceWriter('SampleRate',sampleRate);


%% Definir filtros FIR 
FIR = cell(1,2);
FIR{1} = dsp.FIRFilter('NumeratorSource','Input port');
FIR{2} = dsp.FIRFilter('NumeratorSource','Input port');


%% Inicializar Head Tracker 
% open('HeadTracker.exe')
udpr = dsp.UDPReceiver('RemoteIPAddress', '127.0.0.1',...
                       'LocalIPPort',50050, ...
                       'ReceiveBufferSize', 18); % conectar matlab ao head tracker

%% Processamento em tempo real (fonte fixa no espaco)
audioUnderruns = 0;
audioFiltered = zeros(sigsrc.SamplesPerFrame,2);

yaw = 0;
past_yaw = 0;
pitch = 0;
past_pitch = 0;
slope_yaw = [];
slope_pitch = [];

s_azim = 0;
s_elev = 0;

idx_pos = dsearchn(sourcePosition, [s_azim, s_elev]);
release(deviceWriter)
release(sigsrc)
tic % start head tracker extrapolation time estimate
t2 = 0;

while true
    % Ler orientação atual do HeadTracker.
    py_output = step(udpr);
    
    if ~isempty(py_output)
        data = str2double(split(convertCharsToStrings(char(py_output)), ','));
        yaw = data(1);
        pitch = data(2);
        roll = data(3);        
    end
    
    idx_pos = dsearchn(sourcePosition, [s_azim + yaw, s_elev - pitch]);
%     sourcePosition(idx_pos, :)
    % Obtain a pair of HRTFs at the desired position.
    HRIR = squeeze((hrtfData(idx_pos, :,:))); 
    
    % Read audio from file   
    audioIn = sigsrc();
             
    % Apply HRTFs
    audioFiltered(:,1) = FIR{1}(audioIn, HRIR(1,:)); % Left
    audioFiltered(:,2) = FIR{2}(audioIn, HRIR(2,:)); % Right    
    deviceWriter(squeeze(audioFiltered)); 
end
release(sigsrc)
release(deviceWriter)





function [v, slope] = lininterp1(X, V, x, slope)
% linear interpolation, given set of X and V values, and an x query
% assumes X values are in strictly increasing order
if isempty(slope)
    slope = (x - X(end)) / (X(1) - X(end));
end

v = V(end) * (1 - slope) + V(1) * slope;
end
