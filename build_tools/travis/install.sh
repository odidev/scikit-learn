#!/bin/bash
# This script is meant to be called by the "install" step defined in
# .travis.yml. See https://docs.travis-ci.com/ for more details.
# The behavior of the script is controlled by environment variabled defined
# in the .travis.yml in the top level folder of the project.

# License: 3-clause BSD

# Travis clone scikit-learn/scikit-learn repository in to a local repository.
# We use a cached directory with three scikit-learn repositories (one for each
# matrix entry) from which we pull from local Travis repository. This allows
# us to keep build artefact for gcc + cython, and gain time

set -e

# Fail fast
build_tools/travis/travis_fastfail.sh

# Imports get_dep
source build_tools/shared.sh

echo "List files from cached directories"
echo "pip:"
ls $HOME/.cache/pip

export CC=/usr/lib/ccache/gcc
export CXX=/usr/lib/ccache/g++
# Useful for debugging how ccache is used
# export CCACHE_LOGFILE=/tmp/ccache.log
# ~60M is used by .ccache when compiling from scratch at the time of writing
ccache --max-size 100M --show-stats

# Deactivate the travis-provided virtual environment and setup a
# conda-based environment instead
# If Travvis has language=generic, deactivate does not exist. `|| :` will pass.
deactivate || :

# Install miniconda
if [ `uname -m` == 'aarch64' ]; then
    wget -q "https://github.com/conda-forge/miniforge/releases/download/4.8.2-1/Miniforge3-4.8.2-1-Linux-aarch64.sh"  -O miniconda.sh
    chmod +x miniconda.sh
    ./miniconda.sh -b -p $HOME/miniconda3
    export PATH=$HOME/miniconda3/bin:$PATH
    conda config --set always_yes yes;
else
    fname=Miniconda3-latest-Linux-x86_64.sh
    wget https://repo.continuum.io/miniconda/$fname -O miniconda.sh
    MINICONDA_PATH=$HOME/miniconda
    chmod +x miniconda.sh && ./miniconda.sh -b -p $MINICONDA_PATH
    export PATH=$MINICONDA_PATH/bin:$PATH
fi
conda update --yes conda

# Create environment and install dependencies
conda create -n testenv --yes python=3.7
source activate testenv

pip install --upgrade pip setuptools
if [ `uname -m` == 'aarch64' ]; then
    echo "Installing numpy and scipy master wheels"
    conda install numpy scipy pandas
    conda install cython
    conda install pillow pytest pytest-cov pyamg
    conda install numpydoc matplotlib
    pip install https://github.com/joblib/joblib/archive/master.zip
    pip install pytest-xdist
else    
    echo "Installing numpy and scipy master wheels"
    dev_anaconda_url=https://pypi.anaconda.org/scipy-wheels-nightly/simple
    pip install --pre --upgrade --timeout=60 --extra-index $dev_anaconda_url numpy scipy pandas
    # Cython nightly build should be still fetched from the Rackspace container
    dev_rackspace_url=https://7933911d6844c6c53a7d-47bd50c35cd79bd838daf386af554a83.ssl.cf2.rackcdn.com
    pip install --pre --upgrade --timeout=60 -f $dev_rackspace_url cython
    echo "Installing joblib master"
    pip install https://github.com/joblib/joblib/archive/master.zip
    echo "Installing pillow master"
    pip install https://github.com/python-pillow/Pillow/archive/master.zip
    pip install $(get_dep pytest $PYTEST_VERSION) pytest-cov
    pip install numpydoc matplotlib pyamg
fi

# Build scikit-learn in the install.sh script to collapse the verbose
# build output in the travis output when it succeeds.
python --version
python -c "import numpy; print('numpy %s' % numpy.__version__)"
python -c "import scipy; print('scipy %s' % scipy.__version__)"

if [[ "$BUILD_WITH_ICC" == "true" ]]; then
    wget https://apt.repos.intel.com/intel-gpg-keys/GPG-PUB-KEY-INTEL-SW-PRODUCTS-2023.PUB
    sudo apt-key add GPG-PUB-KEY-INTEL-SW-PRODUCTS-2023.PUB
    rm GPG-PUB-KEY-INTEL-SW-PRODUCTS-2023.PUB
    sudo add-apt-repository "deb https://apt.repos.intel.com/oneapi all main"
    sudo apt-get update
    sudo apt-get install intel-oneapi-icc
    source /opt/intel/inteloneapi/setvars.sh

    # The build_clib command is implicitly used to build libsvm-skl. To compile
    # with a different compiler we also need to specify the compiler for this
    # command.
    python setup.py build_ext --compiler=intelem -i -j 3 build_clib --compiler=intelem
else
    # Use setup.py instead of `pip install -e .` to be able to pass the -j flag
    # to speed-up the building multicore CI machines.
    python setup.py build_ext --inplace -j 3
fi

python setup.py develop

ccache --show-stats
# Useful for debugging how ccache is used
# cat $CCACHE_LOGFILE

# fast fail
build_tools/travis/travis_fastfail.sh
