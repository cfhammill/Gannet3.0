function [AllFramesFTrealign, MRS_struct] = Spectral_Registration(MRS_struct, OnWhat, Dual)
% Spectral registration is a time-domain frequency-and-phase correction
% routine as per Near et al. (2015)
% OnWhat=0 for spectro data, OnWhat=1 for water data
% MM: updates to improve speed and robustness (Jun 2017)

nlinopts = statset('nlinfit');
nlinopts = statset(nlinopts,'MaxIter',1e5,'MaxFunEvals',1e5,'TolX',1e-10,'TolFun',1e-10);

%Dual-channel option only applies registration separately to ONs and OFFs
SpecRegLoop=0;
if nargin == 3
    if Dual == 1
        %We want to run this code twice, once for ONs, once for OFFs.
        SpecRegLoop=1;
    end
end

% Use first N points of time-domain data, where N is the last point where SNR > 3
noise = std(real(MRS_struct.fids.data(ceil(0.75*size(MRS_struct.fids.data,1)):end,:)),[],1);
noise = mean(noise);
signal = mean(abs(MRS_struct.fids.data),2);
SNR = signal./noise;
n = find(SNR > 3);
tMax = n(end);

while SpecRegLoop > -1
    
    if OnWhat %Read water data
        %First, take the complex data and turn it into a real matrix
        flatdata(:,1,:)=real(MRS_struct.fids.data_water(1:tMax,:));
        flatdata(:,2,:)=imag(MRS_struct.fids.data_water(1:tMax,:));
    else % read spectro data
        if nargin == 3
            if Dual == 1
                %This code runs twice, first for ONs, second for OFFs.
                %SpecRegLoop;
                %size(real(MRS_struct.fids.data(:,(MRS_struct.fids.ON_OFF==SpecRegLoop))));
                
                flatdata(:,1,:)=real(MRS_struct.fids.data(1:tMax,(MRS_struct.fids.ON_OFF==SpecRegLoop)));
                flatdata(:,2,:)=imag(MRS_struct.fids.data(1:tMax,(MRS_struct.fids.ON_OFF==SpecRegLoop)));
            end
        else
            % First, take the complex data and turn it into a real matrix
            flatdata(:,1,:)=real(MRS_struct.fids.data(1:tMax,:));
            flatdata(:,2,:)=imag(MRS_struct.fids.data(1:tMax,:));
        end
    end
    
    %Correct to a point 10% into the file (seems better that the actual beginning)
    %AlignRow=ceil(size(flatdata,3)/10);
    %flattarget=squeeze(flatdata(:,:,AlignRow));
    
    % MM (170703): Use median across transients
    flattarget = median(flatdata,3); % median across transients
    
    %Time domain Frequency and Phase Correction
    %Preliminary to fitting:
    parsGuess = [0 0]; %initial freq and phase guess
    parsFit = zeros([size(flatdata,3) 2]);
    CorrPars = zeros([size(flatdata,3) 2]);
    MSE = zeros([1 size(flatdata,3)]);
    input.dwelltime = 1/MRS_struct.p.sw;
    time = (0:1:(MRS_struct.p.npoints-1)).'/MRS_struct.p.sw;
    
    %Fitting to determine frequency and phase corrections
    target = flattarget(:);
    reverseStr = '';
    for corrloop = 1:size(flatdata,3)
        % MM (170227)
        msg = sprintf('\nSpectral registration - Fitting transient: %d', corrloop);
        fprintf([reverseStr, msg]);
        reverseStr = repmat(sprintf('\b'), 1, length(msg));
        
        transient = squeeze(flatdata(:,:,corrloop));
        input.data = transient(:);
        [parsFit(corrloop,:), ~, ~, ~, MSE(corrloop)] = nlinfit(input, target, @FreqPhaseShiftNest, parsGuess, nlinopts);
        parsGuess = parsFit(corrloop,:); %Carry parameters from point to point
    end
    zMSE = zscore(MSE); % standardized MSEs
    
    if OnWhat
        %Applying frequency and phase corrections
        for corrloop=1:size(flatdata,3)
            MRS_struct.fids.data_water(:,corrloop)=MRS_struct.fids.data_water(:,corrloop).*exp(1i*parsFit(corrloop,1)*2*pi*time)*exp(1i*pi/180*parsFit(corrloop,2));
        end
        FullData = MRS_struct.fids.data_water;
        FullData = FullData.* repmat( (exp(-(time)*MRS_struct.p.LB*pi)), [1 size(MRS_struct.fids.data_water,2)]);
        AllFramesFTrealign = fftshift(fft(FullData,MRS_struct.p.ZeroFillTo,1),1);
        
    else
        
        %Applying frequency and phase corrections
        MRS_struct.out.SpecReg.freq(MRS_struct.ii,:) = parsFit(:,1);
        MRS_struct.out.SpecReg.phase(MRS_struct.ii,:) = parsFit(:,2);
        for corrloop=1:size(flatdata,3)
            
            if nargin == 3
                if Dual == 1
                    %Need to get the slot right to put data back into
                    averages_per_dynamic=find(MRS_struct.fids.ON_OFF~=(MRS_struct.fids.ON_OFF(1)),1)-1;
                    dyn=floor((corrloop-1)/averages_per_dynamic); %number of cycles in
                    ind=mod((corrloop-1),averages_per_dynamic)+1; %number in current cycle
                    
                    if SpecRegLoop == 1
                        if MRS_struct.fids.ON_OFF(1) == 1
                            corrloop_d = dyn*averages_per_dynamic*2+ind;
                        else
                            corrloop_d = dyn*averages_per_dynamic*2+averages_per_dynamic+ind;
                        end
                    else
                        if MRS_struct.fids.ON_OFF(1) == 1
                            corrloop_d = dyn*averages_per_dynamic*2+averages_per_dynamic+ind;
                        else
                            corrloop_d = dyn*averages_per_dynamic*2+ind;
                        end
                    end
                    
                    MRS_struct.fids.data_align(:,corrloop_d)=MRS_struct.fids.data(:,corrloop_d).*exp(1i*parsFit(corrloop,1)*2*pi*time)*exp(1i*pi/180*parsFit(corrloop,2));
                end
                CorrPars(corrloop_d,:)=parsFit(corrloop,:);
            else
                corrloop_d=corrloop;
                MRS_struct.fids.data_align(:,corrloop_d)=MRS_struct.fids.data(:,corrloop_d).*exp(1i*parsFit(corrloop,1)*2*pi*time)*exp(1i*pi/180*parsFit(corrloop,2));
                CorrPars(corrloop_d,:)=parsFit(corrloop,:);
            end
            
        end
        
        if SpecRegLoop == 0
            FullData = MRS_struct.fids.data_align;
            FullData = FullData.* repmat( (exp(-(time)*MRS_struct.p.LB*pi)), [1 size(MRS_struct.fids.data,2)]);
            AllFramesFTrealign = fftshift(fft(FullData,MRS_struct.p.ZeroFillTo,1),1);
            
            % In frequency domain, move Cr to 3.02 and get phase 'right' as opposed to 'consistent'
            freqbounds = MRS_struct.spec.freq <= 3.6 & MRS_struct.spec.freq >= 2.6; % MM (170227)
            freq = MRS_struct.spec.freq(freqbounds);
            %Do some detective work to figure out the initial parameters
            ChoCrMeanSpec = mean(AllFramesFTrealign(freqbounds,:),2);
            Baseline_offset=real(ChoCrMeanSpec(1)+ChoCrMeanSpec(end))/2;
            Width_estimate=0.05;%ppm
            Area_estimate=(max(real(ChoCrMeanSpec))-min(real(ChoCrMeanSpec)))*Width_estimate*4;
            ChoCr_initx = [Area_estimate Width_estimate 3.02 0 Baseline_offset 0 1] .* [1 2*MRS_struct.p.LarmorFreq MRS_struct.p.LarmorFreq 180/pi 1 1 1];
            
            if nargin == 3
                if Dual == 1
                    %This bit is silly - we don't want to do OFF-to-ON based on the Cr signal
                    ChoCrMeanSpecON = mean(AllFramesFTrealign(freqbounds,(MRS_struct.fids.ON_OFF==1)),2);
                    ChoCrMeanSpecOFF = mean(AllFramesFTrealign(freqbounds,(MRS_struct.fids.ON_OFF==0)),2);
                    ChoCrMeanSpecFitON = FitChoCr(freq, ChoCrMeanSpecON, ChoCr_initx,MRS_struct.p.LarmorFreq);
                    ChoCrMeanSpecFitOFF = FitChoCr(freq, ChoCrMeanSpecOFF, ChoCr_initx,MRS_struct.p.LarmorFreq);
                    AllFramesFTrealign(:,(MRS_struct.fids.ON_OFF==1))=AllFramesFTrealign(:,(MRS_struct.fids.ON_OFF==1))*exp(1i*pi/180*(ChoCrMeanSpecFitON(4))); % phase
                    AllFramesFTrealign(:,(MRS_struct.fids.ON_OFF==0))=AllFramesFTrealign(:,(MRS_struct.fids.ON_OFF==0))*exp(1i*pi/180*(ChoCrMeanSpecFitOFF(4))); % phase
                    
                    ChoCrFreqShiftON = ChoCrMeanSpecFitON(3);
                    ChoCrFreqShiftON = ChoCrFreqShiftON - 3.02*MRS_struct.p.LarmorFreq;
                    ChoCrFreqShiftON = ChoCrFreqShiftON ./ (MRS_struct.p.LarmorFreq * abs(MRS_struct.spec.freq(1) - MRS_struct.spec.freq(2)));
                    ChoCrFreqShift_pointsON = round(ChoCrFreqShiftON);
                    AllFramesFTrealign(:,(MRS_struct.fids.ON_OFF==1)) = circshift(AllFramesFTrealign(:,(MRS_struct.fids.ON_OFF==1)), ChoCrFreqShift_pointsON); % freq
                    ChoCrFreqShiftOFF = ChoCrMeanSpecFitOFF(3);
                    ChoCrFreqShiftOFF = ChoCrFreqShiftOFF - 3.02*MRS_struct.p.LarmorFreq;
                    ChoCrFreqShiftOFF = ChoCrFreqShiftOFF ./ (MRS_struct.p.LarmorFreq * abs(MRS_struct.spec.freq(1) - MRS_struct.spec.freq(2)));
                    ChoCrFreqShift_pointsOFF = round(ChoCrFreqShiftOFF);
                    AllFramesFTrealign(:,(MRS_struct.fids.ON_OFF==0)) = circshift(AllFramesFTrealign(:,(MRS_struct.fids.ON_OFF==0)), ChoCrFreqShift_pointsOFF); % freq
                    
                end
            else
                ChoCrMeanSpecFit = FitChoCr(freq, ChoCrMeanSpec, ChoCr_initx, MRS_struct.p.LarmorFreq);
                AllFramesFTrealign = AllFramesFTrealign*exp(1i*pi/180*(ChoCrMeanSpecFit(4))); % phase
                ChoCrFreqShift = ChoCrMeanSpecFit(3);
                ChoCrFreqShift = ChoCrFreqShift - 3.02*MRS_struct.p.LarmorFreq;
                ChoCrFreqShift = ChoCrFreqShift ./ (MRS_struct.p.LarmorFreq * abs(MRS_struct.spec.freq(1) - MRS_struct.spec.freq(2)));
                ChoCrFreqShift_points = round(ChoCrFreqShift);
                AllFramesFTrealign = circshift(AllFramesFTrealign, ChoCrFreqShift_points); % freq
            end
            
            %Some output
            MRS_struct.out.FreqStdevHz(MRS_struct.ii) = std(parsFit(:,1),1);
            
            % Reject transients that are greater than +/-3 st. devs. of MSEs (MM: 171004)
            MRS_struct.out.reject(:,MRS_struct.ii) = zMSE > 3 | zMSE < -3;
            
        end
    end
    
    SpecRegLoop=SpecRegLoop-1;
    
end

fprintf('\n');

end

