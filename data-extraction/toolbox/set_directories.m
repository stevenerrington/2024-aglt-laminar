function dirs = set_directories()

if ispc
     % Setup directories
    dirs.raw_data  = 'C:\KIKUCHI-LOCAL\data\ephys\raw\';
    dirs.bin_data  = 'C:\KIKUCHI-LOCAL\data\ephys\bin\';
    dirs.kilosort   = 'C:\KIKUCHI-LOCAL\data\ephys\ks\';
    dirs.mat_data = 'C:\KIKUCHI-LOCAL\data\ephys\mat';
    dirs.doc_data = 'C:\KIKUCHI-LOCAL\script\2024-aglt-laminar\data-extraction\doc';
    dirs.root = 'C:\KIKUCHI-LOCAL\script\2024-aglt-laminar\';

elseif ismac

     % Setup directories
    dirs.raw_data  = 'N/A';
    dirs.bin_data  = 'N/A';
    dirs.kilosort   = 'N/A';
    dirs.mat_data = '/Users/stevenerrington/Library/CloudStorage/OneDrive-NewcastleUniversity/Research/agl_t/mat';
    dirs.doc_data = '/Users/stevenerrington/Desktop/Projects/2024-aglt-laminar/data-extraction/doc';
    dirs.root = '/Users/stevenerrington/Desktop/Projects/2024-aglt-laminar/';


end
