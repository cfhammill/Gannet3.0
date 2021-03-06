function GannetPlotPrePostAlign2(MRS_struct, vox, ii)
% Plots pre and post alignment spectra in MRSLoadPfiles
% 110214:  Scale spectra by the peak _height_ of water
%          Plot multiple spectra as a stack - baselines offset
%            by mean height of GABA
% Updates by MGSaleh 2016, MM 2017

for kk = 1:length(vox)
    
    if MRS_struct.p.HERMES
        
        numspec = 4;        
        SpectraToPlot = [MRS_struct.spec.(vox{kk}).(sprintf('%s',MRS_struct.p.target)).diff(ii,:); ...
            MRS_struct.spec.(vox{kk}).(sprintf('%s',MRS_struct.p.target)).diff_noalign(ii,:); ...
            MRS_struct.spec.(vox{kk}).(sprintf('%s',MRS_struct.p.target2)).diff(ii,:); ...
            MRS_struct.spec.(vox{kk}).(sprintf('%s',MRS_struct.p.target2)).diff_noalign(ii,:)];
        
        % Estimate baseline from between GABAGlx or Lac and GSH. The values might be changed depending on the future choice of metabolites
        % MM (170705)
        if strcmp(MRS_struct.p.target2, 'Lac')
            Glx_r_GABA_l = MRS_struct.spec.freq <= 1.5 & MRS_struct.spec.freq >= 1.0;
            Glx_r_GABA_r = MRS_struct.spec.freq <= 1.5 & MRS_struct.spec.freq >= 0.5;
        else
            Glx_r_GABA_l = MRS_struct.spec.freq <= 3.1 & MRS_struct.spec.freq >= 2.9;
            Glx_r_GABA_r = MRS_struct.spec.freq <= 3.1 & MRS_struct.spec.freq >= 2.8;
        end
        
        specbaseline = (mean(real(SpectraToPlot(1,Glx_r_GABA_l)),2));
        
    else
        
        numspec = 2;
        SpectraToPlot = [MRS_struct.spec.(vox{kk}).(sprintf('%s',MRS_struct.p.target)).diff(ii,:); ...
            MRS_struct.spec.(vox{kk}).(sprintf('%s',MRS_struct.p.target)).diff_noalign(ii,:)];
        
        % Estimate baseline from between Glx and GABA
        % MM (170705)
        Glx_r_GABA_l = MRS_struct.spec.freq <= 3.6 & MRS_struct.spec.freq >= 3.3;
        Glx_r_GABA_r = MRS_struct.spec.freq <= 3.6 & MRS_struct.spec.freq >= 2.8;
        
        specbaseline = (mean(real(SpectraToPlot(1,Glx_r_GABA_l)),2));
        
    end
    
    if MRS_struct.p.HERMES
        
        % Averaged gaba height across all scans - to estimate stack spacing
        gabaheight = abs(max(SpectraToPlot(1,Glx_r_GABA_r),[],2));
        gabaheight = mean(gabaheight);
        plotstackoffset = (0:(numspec-1))';
        
        if strcmp(MRS_struct.p.target2, 'Lac')
            plotstackoffset = plotstackoffset * 0.5 * gabaheight;
        else
            plotstackoffset = plotstackoffset * 1.75 * gabaheight;
        end
        plotstackoffset = plotstackoffset - specbaseline;
        
        target = {MRS_struct.p.target, MRS_struct.p.target2};
        model = cell(1,2);
        freqbounds = cell(1,2);
        for trg = 1:length(target)
            switch target{trg}
                case 'GABA'
                    freqbounds{trg} = find(MRS_struct.spec.freq <= 3.55 & MRS_struct.spec.freq >= 2.79);
                    model{trg} = GaussModel(MRS_struct.out.(vox{kk}).GABA.ModelParam(ii,:),MRS_struct.spec.freq(freqbounds{trg}));
                case 'GSH'
                    freqbounds{trg} = find(MRS_struct.spec.freq <= 3.3 & MRS_struct.spec.freq >= 2.35);
                    model{trg} = FiveGaussModel(MRS_struct.out.(vox{kk}).GSH.ModelParam(ii,:),MRS_struct.spec.freq(freqbounds{trg}));
                case 'GABAGlx'
                    freqbounds{trg} = find(MRS_struct.spec.freq <= 4.1 & MRS_struct.spec.freq >= 2.79);
                    model{trg} = GABAGlxModel(MRS_struct.out.(vox{kk}).GABA.ModelParam(ii,:),MRS_struct.spec.freq(freqbounds{trg}));
                case 'Lac'
                    freqbounds{trg} = find(MRS_struct.spec.freq <= 1.8 & MRS_struct.spec.freq >= 0.5);
                    model{trg} = FourGaussModel(MRS_struct.out.(vox{kk}).Lac.ModelParam(ii,:),MRS_struct.spec.freq(freqbounds{trg}));
            end
        end
        
        aa = 1.2;
        hold on;
        %plot(MRS_struct.spec.freq, aa*real(SpectraToPlot(2,:)), 'Color', 'r');
        plot(MRS_struct.spec.freq, aa*real(SpectraToPlot(1,:)), 'Color', 'k');
        plot(MRS_struct.spec.freq(freqbounds{1}), aa*model{1}, 'r');
        shift = repmat(plotstackoffset, [1 length(SpectraToPlot(1,:))]);
        shift = [max(shift,[],1); max(shift,[],1)];
        SpectraToPlot(3:4,:) = SpectraToPlot(3:4,:) + shift;
        %plot(MRS_struct.spec.freq, aa*real(SpectraToPlot(4,:)), 'Color', 'r');
        plot(MRS_struct.spec.freq, aa*real(SpectraToPlot(3,:)), 'Color', 'k');
        plot(MRS_struct.spec.freq(freqbounds{2}), aa*(model{2} + shift(1)), 'r');
        hold off;
        
        if strcmp(MRS_struct.p.target2, 'Lac')
            yaxismax = (numspec + 1.0) * 0.5 * gabaheight;
        else
            yaxismax = (numspec + 1.0) * 1.75 * gabaheight;
            
        end
        yaxismin = -2*gabaheight;        
        if yaxismax < yaxismin
            [yaxismax, yaxismin] = deal(yaxismin, yaxismax); % MM (170701)
        end        
        
    else
        
        % Averaged gaba height across all scans - to estimate stack spacing
        gabaheight = abs(max(SpectraToPlot([1 2],Glx_r_GABA_r),[],2));
        gabaheight = max(gabaheight);
        plotstackoffset = (0:(numspec-1))';
        plotstackoffset = plotstackoffset * gabaheight;
        plotstackoffset = plotstackoffset - specbaseline;
        
        switch MRS_struct.p.target
            case 'GABA'
                freqbounds = find(MRS_struct.spec.freq <= 3.55 & MRS_struct.spec.freq >= 2.79);
                model = GaussModel(MRS_struct.out.(vox{kk}).GABA.ModelParam(ii,:),MRS_struct.spec.freq(freqbounds));
            case 'GSH'
                freqbounds = find(MRS_struct.spec.freq <= 3.3 & MRS_struct.spec.freq >= 2.35);
                model = FiveGaussModel(MRS_struct.out.(vox{kk}).GSH.ModelParam(ii,:),MRS_struct.spec.freq(freqbounds));
            case 'GABAGlx'
                freqbounds = find(MRS_struct.spec.freq <= 4.1 & MRS_struct.spec.freq >= 2.79);
                model = GABAGlxModel(MRS_struct.out.(vox{kk}).GABA.ModelParam(ii,:),MRS_struct.spec.freq(freqbounds));
            case 'Lac'
                freqbounds = find(MRS_struct.spec.freq <= 1.8 & MRS_struct.spec.freq >= 0.5);
                model = FourGaussModel(MRS_struct.out.(vox{kk}).Lac.ModelParam(ii,:),MRS_struct.spec.freq(freqbounds));
        end
        
        SpectraToPlot = SpectraToPlot + repmat(plotstackoffset, [1 length(SpectraToPlot(1,:))]);
        hold on;
        %plot(MRS_struct.spec.freq, real(SpectraToPlot(2,:)), 'Color', 'r');
        plot(MRS_struct.spec.freq, real(SpectraToPlot(1,:)), 'Color', 'k');
        plot(MRS_struct.spec.freq(freqbounds), model + plotstackoffset(1), 'r');
        hold off;
        
        yaxismax = 1.5*abs(max(max(real(SpectraToPlot([1 2],Glx_r_GABA_r)),[],2)));
        yaxismin = -10.0*abs(min(min(real(SpectraToPlot([1 2],Glx_r_GABA_r)),[],2)));
        if yaxismax < yaxismin
            [yaxismax, yaxismin] = deal(yaxismin, yaxismax); % MM (170701)
        end
        
    end
    
    box on;
    legendtxt = {'data','model'};
    hl = legend(legendtxt);
    set(hl,'EdgeColor',[1 1 1]);
    set(gca,'XDir','reverse');
    axis([0 5 yaxismin yaxismax]);
    
end

