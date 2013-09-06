#!/bin/sh
$4/mussh/mussh -H ${2} -c "cd ${1};git pull" -m0;
