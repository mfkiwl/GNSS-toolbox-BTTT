function xtr2MPskyplot(xtrFileName, MPcode, saveFig, options)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Function to read Gnut-Anubis XTR output file and make MP skyplot graphs.
% Process iterates through all available satellite systems (it will
% detect automatically) and try to plot given MP combination.
%
% Input:
% xtrFileName - name of XTR file
% MPcode - 2-char representation of MP code combination to plot
%        - values corresponding to RINEX v2 code measurements
%
% Optional:
% saveFig - true/false flag to export plots to PNG file (default: true)
% options - structure with the following settings:
%      colorBarLimits = [0 120]; % Range of colorbar
%      colorBarTicks = 0:20:120; % Ticks on colorbar 
%      figResolution = '200';    % Output PNG resolution
%      cutOffValue = 0;          % Value of elevation cutoff on skyplots
%
% Requirements:
% polarplot3d.m, findGNSTypes.m, dataCell2matrix.m, getNoSatZone.m
%
% Peter Spanik, 7.10.2018
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% Close all opened figures
close all

% Default options
opt = struct('colorBarLimits',[0, 120],...
                    'colorBarTicks', 0:20:120,...
                    'figResolution','200',...
                    'cutOffValue',0);

% Check input values
if nargin == 2
   saveFig = true;
   options = opt;
   if ~ischar(xtrFileName) || ~ischar(MPcode)
      error('Inputs "xtrFileName" and "MPcode" have to be strings!') 
   end
   
elseif nargin == 3
    saveFig = logical(saveFig);
   if ~ischar(xtrFileName) || ~ischar(MPcode) || numel(saveFig) ~= 1 
      error('Inputs "xtrFileName","MPcode" have to be strings and "saveFig" has to be single value!') 
   end
   options = opt;

elseif nargin == 4
   if numel(options) ~= 3
      error('Input variable "limAndTicks" have to be cell of the following form {[1x2 array], [1xn array], [1xn char]}!') 
   end
else
   error('Only 2, 3 or 4 input values are allowed!') 
end

% File loading
finp = fopen(xtrFileName,'r');
raw = textscan(finp,'%s','Delimiter','\n','Whitespace','');
data = raw{1,1};

% Find empty lines in XTR file and remove them
data = data(~cellfun(@(c) isempty(c), data));

% Find indices of Main Chapters (#)
GNScell = findGNSTypes(data);

% Set custom colormap -> empty bin = white
myColorMap = colormap(jet); close; % Command colormap open figure!
myColorMap = [[1,1,1]; myColorMap];

% Satellite's data loading
for i = 1:length(GNScell)
    % Find position estimate
    selpos = cellfun(@(c) strcmp(['=XYZ', GNScell{i}],c(1:7)), data);
    postext = char(data(selpos));
    pos = str2num(postext(30:76));
    
    % Elevation loading
    selELE_GNS = cellfun(@(c) strcmp([GNScell{i}, 'ELE'],c(2:7)), data);
    dataCell = data(selELE_GNS);
    [timeStamp, meanVal, dataMatrix] = dataCell2matrix(dataCell);
    ELE.(GNScell{i}).time = timeStamp;
    ELE.(GNScell{i}).meanVals = meanVal;
    ELE.(GNScell{i}).vals = dataMatrix;
    sel1 = ~isnan(dataMatrix);
    
    % Azimuth loading
    selAZI_GNS = cellfun(@(c) strcmp([GNScell{i}, 'AZI'],c(2:7)), data);
    dataCell = data(selAZI_GNS);
    [timeStamp, meanVal, dataMatrix] = dataCell2matrix(dataCell);
    AZI.(GNScell{i}).time = timeStamp;
    AZI.(GNScell{i}).meanVals = meanVal;
    AZI.(GNScell{i}).vals = dataMatrix;
    sel2 = ~isnan(dataMatrix);
    
    % Check ELE and AZI size
    if size(sel1) == size(sel2)
       % Get timestamps
       if all(ELE.(GNScell{i}).time == AZI.(GNScell{i}).time)
          timeStampsUni = timeStamp;
       end
    else
       error('Reading ELE and AZI failed, not equal number of ELE and AZI epochs!')
    end
    
    % Multipath loading
    selMP_GNS = cellfun(@(c) strcmp([' ', GNScell{i}, 'M', MPcode], c(1:7)), data);
    if nnz(selMP_GNS) == 0
        warning('For %s system MP combination %s not available!',GNScell{i},MPcode)
        continue
    end
    dataCell = data(selMP_GNS);
    [timeStamp, meanVal, dataMatrix] = dataCell2matrix(dataCell);
    MP.(GNScell{i}).time = timeStamp;
    MP.(GNScell{i}).meanVals = meanVal;
    if size(dataMatrix,1) ~= size(sel1,1)
        % Find indices logical indices of not missing values
        idxNotMissing = ismember(timeStampsUni,timeStamp);
        
        % Alocate new array of values with correct dimensions
        newdataMatrix = nan(numel(timeStampsUni),size(dataMatrix,2));
        
        % Assign not missing values from old array to new one
        newdataMatrix(idxNotMissing,:) = dataMatrix;
        dataMatrix = newdataMatrix;
    end
    
    MP.(GNScell{i}).vals = dataMatrix;
    sel3 = ~isnan(dataMatrix);

    sel = sel1 & sel2 & sel3;
    ELE.(GNScell{i}).vector = ELE.(GNScell{i}).vals(sel);
    AZI.(GNScell{i}).vector = AZI.(GNScell{i}).vals(sel);
    MP.(GNScell{i}).vector = MP.(GNScell{i}).vals(sel);
    
    % Interpolate to regular grid
    aziBins = 0:3:360;
    eleBins = 0:3:90;
    [azig, eleg] = meshgrid(aziBins, eleBins);
    F = scatteredInterpolant(AZI.(GNScell{i}).vector,ELE.(GNScell{i}).vector,MP.(GNScell{i}).vector,'linear','none');
    visibleBins = getVisibilityMask(AZI.(GNScell{i}).vector,ELE.(GNScell{i}).vector,[3, 3],options.cutOffValue);
    mpg = F(azig,eleg);
    mpg(isnan(mpg)) = -1;
    mpg(~visibleBins) = -1;
    
    % Determine noSatZone bins
    [x_edge,y_edge] = getNoSatZone(GNScell{i},pos);
    xq = (90 - eleg).*sind(azig);
    yq = (90 - eleg).*cosd(azig);
    in = inpolygon(xq,yq,x_edge,y_edge);
    mpg(in) = -1;
    
    % Create figure
    figure('Position',[300 100 700 480],'NumberTitle', 'off','Resize','off')
    polarplot3d(flipud(mpg),'PlotType','surfn','RadialRange',[0 90],'PolarGrid',{6,12},'GridStyle',':','AxisLocation','surf');
    view(90,-90)
    
    colormap(myColorMap)
    c = colorbar;
    colLimits = options.colorBarLimits;
    colLimits(1) = colLimits(1) + 5;
    c.Limits = colLimits;
    c.Ticks = options.colorBarTicks;
    c.Position = [c.Position(1)*1.02, c.Position(2)*1.4, 0.8*c.Position(3), c.Position(4)*0.9];
    c.TickDirection = 'in';
    c.LineWidth = 1.1;
    c.FontSize = 10;
    % Transforming common values to vectors
    
    caxis(options.colorBarLimits)
    ylabel(c,sprintf('%s RMS MP%s value (cm)',GNScell{i},MPcode),'fontsize',10,'fontname','arial')
    axis equal
    axis tight
    axis off
    hold on
    text(60,0,-100,'30','FontSize',10,'HorizontalAlignment','center','background','w','fontname','arial','FontWeight','bold')
    text(30,0,-100,'60','FontSize',10,'HorizontalAlignment','center','background','w','fontname','arial','FontWeight','bold')
    
    % Exporting figure
    if saveFig == true
       splittedInputName = strsplit(xtrFileName,'.');  
       figName = [splittedInputName{1}, '_', GNScell{i}, '_MP', MPcode];
       print(figName,'-dpng',sprintf('-r%s',options.figResolution))
    end
end