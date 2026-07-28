#!/usr/bin/env bash

# This configuration file centralizes all paths and variables required for the remote cluster submission.
# Update these paths to match your local and remote environments.

# working dir
export LOCAL_WORKDIR="/mnt/c/Users/a.gentili/Downloads/workflow-driver"
export REMOTE_WORKDIR="/leonardo_work/PHD_gentili/workflow-driver"

# environment dir
export LOCAL_VENV="${LOCAL_WORKDIR}/venv"
export REMOTE_VENV="${REMOTE_WORKDIR}/venv"

# cache dir
export LOCAL_CACHE="/home/agentili/.cache"
export REMOTE_CACHE="/leonardo/home/userinternal/agentil1/.cache"

# host name
export REMOTE_HOST="leonardo"
export REMOTE_STORAGE_HOST="login.leonardo.cineca.it:22"
