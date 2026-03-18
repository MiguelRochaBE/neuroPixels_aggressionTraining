

function customVectorSlice(saveName, apCoord, targetAcronym, av, st)

b = allenCCFbregma;
avSlice = squeeze(av(b(1)-apCoord*100,:,:));

% targetID = st(strcmp(st.acronym, targetAcronym),:).index+1;
idx = find(strcmp(st.acronym, targetAcronym)); strpath = sprintf('/%d/', st(idx,:).id);
targetID = find(contains(st.structure_id_path, strpath));

f = figure; f.Color = 'k';

% [coords, coordsReg, h] = sliceOutlineWithRegionVec(avSlice, targetID, 'r', gca);

im = sliceOutlineWithRegion(avSlice);
c = contourc(double(im(:,:,1)), [128 128]);
coords = makeSmoothCoords(c);

clear h
for cidx = 1:numel(coords)
    h(cidx) = plot(coords(cidx).x,coords(cidx).y,'LineWidth', 1.0, 'Color', [0.5 0.5 0.5]); hold on;
end

regColor = [0 1 1];
c = contourc(double(ismember(avSlice,uint16(targetID))), [0.5 0.5]);
coordsReg = makeSmoothCoords(c);

for cidx = 1:numel(coordsReg)
    plot(coordsReg(cidx).x,coordsReg(cidx).y, 'Color', regColor, 'LineWidth', 1.5); hold on;
end

axis image;
axis off;
set(gca, 'YDir', 'reverse');


print(gcf, '-dpdf', saveName)