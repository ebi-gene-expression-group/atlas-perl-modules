[![Anaconda-Server Badge](https://anaconda.org/bioconda/perl-atlas-modules/badges/installer/conda.svg)](https://conda.anaconda.org/bioconda)

# Atlas in house perl modules

Repository includes internal perl modules that is used for processing studies in atlas data production pipeline particularly handling MAGE-TABs, baseline and differential analysis, zooma mappings, release data exports. 

## Install

perl-atlas-modules can be installed from Bioconda:

```
conda install -c bioconda perl-atlas-modules
```

## Configuration 

perl-atlas-modules will look for configuration files in a directory specified by the enviironment variable `ATLAS_META_CONFIG` if that variable is set, and will otherwise look at the [supporting_files](supporting_files) directory, which is installed along with the perl modules as part of the Bioconda install method above. The '.default' files are used to initialise default configurations where not already present. 


