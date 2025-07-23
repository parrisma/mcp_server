#!/bin/bash

# Create Conda environment with Python 3.11
conda create -y -n openwebui python=3.11

# Activate the environment
source activate openwebui

# Install packages from conda-forge
conda install -y -c conda-forge fastmcp
conda install -y -c conda-forge python-jose
conda install -y -c conda-forge httpx
conda install -y -c conda-forge pytest
conda install -y -c conda-forge fastapi
conda install -y -c conda-forge uvicorn
conda install -y -c conda-forge pyjwt
