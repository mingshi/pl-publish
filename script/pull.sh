#!/bin/sh
mussh/mussh -H ${2} -c "cd ${1};git pull" -m0
