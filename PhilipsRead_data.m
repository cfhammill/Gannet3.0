function [ MRS_struct ] = PhilipsRead_data(MRS_struct, fname)
%   Reads Philips DATA/LIST files into Gannet.
%
%   Author:
%       Dr. Georg Oeltzschner (Johns Hopkins University, 2018-03-02)
%       goeltzs1@jhmi.edu
%   
%   Credits:
%       This code uses the function
%       loadRawKspace.m
%       from the excellent "Matlab raw kspace tools" toolbox
%       (Wouter Potters, Academic Medical Center, Amsterdam, NL)
%       https://bitbucket.org/wpotters/matlab-raw-kspace-tools
%
%   History:
%       2018-03-02: First version.
%       2018-03-26: Fixed bug - phase correction is NOT performed if coil
%       combination is based on SENSE reconstruction (e.g. MEGA-PRIAM)

ii = MRS_struct.ii;

%% Extract information from SPAR files that is not in DATA/LIST

% Get the appropriate _act.spar
spar_files = dir('*_act.spar'); % it's automatically case-insensitive
% If more than one .spar file is found, select one
if(length(spar_files)>1)
    disp('More than one .spar file found:');
    for kk = 1:length(spar_files)
        fprintf('# %i --- %s\n',kk,spar_files(kk).name);
    end
    result = input('Select the correct spar file corresponding to the DATA/LIST file you want to load (input number): ');
    if isempty(result)
        return
    end
else
    result = 1;
end
spar_file = [spar_files(result).name];

% Open spar file and read parameters
sparname = fopen(spar_file,'r');
sparheader = textscan(sparname, '%s');
sparheader = sparheader{1};
sparidx=find(ismember(sparheader, 'samples')==1); % number of data points
MRS_struct.p.npoints(ii) = str2double(sparheader{sparidx+2});
sparidx=find(ismember(sparheader, 'rows')==1); % number of rows
MRS_struct.p.nrows(ii) = str2double(sparheader{sparidx+2});
sparidx=find(ismember(sparheader, 'averages')==1); % number of averages
MRS_struct.p.Navg(ii) = MRS_struct.p.nrows(MRS_struct.ii) * str2double(sparheader{sparidx+2});
sparidx=find(ismember(sparheader, 'repetition_time')==1); % TR
MRS_struct.p.TR(ii) = str2double(sparheader{sparidx+2});
sparidx=find(ismember(sparheader, 'echo_time')==1); % TE
MRS_struct.p.TE(ii) = str2double(sparheader{sparidx+2}); % 
sparidx=find(ismember(sparheader, 'synthesizer_frequency')==1); % F0
MRS_struct.p.LarmorFreq(ii) = str2double(sparheader{sparidx+2})/1e6;
sparidx=find(ismember(sparheader, 'sample_frequency')==1); % readout bandwidth
MRS_struct.p.sw(ii) = str2double(sparheader{sparidx+2});

% Read voxel geometry information.
% THIS IS IN THE ORDER LR-AP-FH!
sparidx=find(ismember(sparheader, 'lr_size')==1); % voxel size 
MRS_struct.p.voxdim(ii,1) = str2double(sparheader{sparidx+2});
sparidx=find(ismember(sparheader, 'ap_size')==1);
MRS_struct.p.voxdim(ii,2) = str2double(sparheader{sparidx+2});
sparidx=find(ismember(sparheader, 'cc_size')==1);
MRS_struct.p.voxdim(ii,3) = str2double(sparheader{sparidx+2});
sparidx=find(ismember(sparheader, 'lr_off_center')==1); % voxel center offset
MRS_struct.p.voxoff(ii,1) = str2double(sparheader{sparidx+2});
sparidx=find(ismember(sparheader, 'ap_off_center')==1);
MRS_struct.p.voxoff(ii,2) = str2double(sparheader{sparidx+2});
sparidx=find(ismember(sparheader, 'cc_off_center')==1);
MRS_struct.p.voxoff(ii,3) = str2double(sparheader{sparidx+2});
sparidx=find(ismember(sparheader, 'lr_angulation')==1); % voxel angulation (radians)
MRS_struct.p.voxang(ii,1) = str2double(sparheader{sparidx+2});
sparidx=find(ismember(sparheader, 'ap_angulation')==1);
MRS_struct.p.voxang(ii,2) = str2double(sparheader{sparidx+2});
sparidx=find(ismember(sparheader, 'cc_angulation')==1);
MRS_struct.p.voxang(ii,3) = str2double(sparheader{sparidx+2});
fclose(sparname);

%% Extract information from SIN files that is not in DATA/LIST
% This is important for calculations based on receiver-coil 
% sensitivity maps, like MEGA-PRIAM.

if MRS_struct.p.PRIAM
    % Get the appropriate *.sin
    sin_files = dir('*.sin'); % it's automatically case-insensitive
    % If more than one .spar file is found, select one
    if(length(sin_files)>1)
        disp('More than one .sin file found:');
        for kk = 1:length(sin_files)
            fprintf('# %i --- %s\n',kk,sin_files(kk).name);
        end
        result = input('Select the correct sin file corresponding to the DATA/LIST file you want to load (input number): ');
        if isempty(result)
            return
        end
    else
        result = 1;
    end
    sin_file = [sin_files(result).name];
    MRS_struct.p.sin_info = get_sin_info(sin_file);
end

%% Load and process DATA/LIST
[data] = loadRawKspace(fname);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Determine dimensions of the acquisition
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% Determine number of channels
n_coils = length(unique(data.chan));

% Determine number of mixes
n_mixes = length(unique(data.mix));

% Determine number of averages per mix
n_averages = data.kspace_properties.number_of_signal_averages;
n_av_edit = n_averages(1);
if n_mixes == 2
    n_av_water = n_averages(2); % if second mix exists, it is water
end
% This will be the NSA as specified on the exam card for the water-suppressed mix (mix = 0)
% and the NSA as specified on the exam card for the water-suppressed mix (mix = 1);

% Determine number of dynamics per NSA. It is not stored in the dynamics
% field, but rather in extra attributes. Could be different for different
% software versions, need to check!
n_dyns = data.kspace_properties.number_of_extra_attribute_1_values;
n_dyns_edit = n_dyns(1);
if n_mixes == 2
    n_dyns_water = n_dyns(2); % if second mix exists, it is water
end
% Since dynamics are set globally on the exam card, this will be the same
% for both - it will only be the true value for the water-suppressed mix

% Determine number of data points per scan
n_points = data.kspace_properties.F_resolution(1);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Start splitting the list of total scans into its parts:
% Noise scans, water-suppressed scans, and water-unsuppressed scans.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% Noise scans have the data type 'NOI'
isnoise = strcmp(data.typ,'NOI');
fids_noise = cell2mat(data.complexdata(isnoise));
n_av_noise = size(fids_noise,1) ./ n_coils;

% Separate the water-suppressed from the water-unsuppressed scans.
% Water-suppressed scans have the data type 'STD' and mix index 0:
isedit = strcmp(data.typ,'STD') & (data.mix == 0);
fids_edit = cell2mat(data.complexdata(isedit));
% Reshape the water-suppressed data
fids_edit = reshape(fids_edit,[n_coils n_av_edit*n_dyns_edit n_points]);

% Phase by multiplying with normalized complex conjugate of first point
if ~MRS_struct.p.PRIAM 
    % Don't do this when using SENSE reconstruction!
    conj_norm = conj(fids_edit(:,:,1)) ./ abs(conj(fids_edit(:,:,1)));
    fids_edit_ph = fids_edit .* repmat(conj_norm, [1 1 n_points]);
else
    fids_edit_ph = fids_edit;
end

% Save to MRS_struct
MRS_struct.fids.data = fids_edit_ph;

% Water-unsuppressed scans have the data type 'STD' and mix index 1:
if n_mixes == 2
    iswater = strcmp(data.typ,'STD') & (data.mix == 1);
    fids_water = cell2mat(data.complexdata(iswater));
    
    % Reshape the water-unsuppressed data
    fids_water = reshape(fids_water,[n_coils n_av_water n_points]);
    
    % Phase by multiplying with normalized complex conjugate of first point
    if ~MRS_struct.p.PRIAM
        % Don't do this when using SENSE reconstruction!
        conj_norm = conj(fids_water(:,:,1)) ./ abs(conj(fids_water(:,:,1)));
        fids_water_ph = fids_water .* repmat(conj_norm, [1 1 n_points]);
    else
        fids_water_ph = fids_water;
    end
    
    % Save to MRS_struct
    MRS_struct.fids.data_water = fids_water_ph;
end

% Write parameters to MRS_struct
MRS_struct.fids.data_noise = fids_noise;
MRS_struct.p.Ncoils(ii) = n_coils;
MRS_struct.p.npoints(ii) = n_points;
MRS_struct.p.Navg(ii) = n_av_edit*n_dyns_edit;
MRS_struct.p.Nwateravg(ii) = n_av_water;
MRS_struct.p.Nnoiseavg(ii) = n_av_noise;

end





