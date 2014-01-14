#!/bin/sh
if [ -z "$5" ];then
    $4/mussh/mussh -H ${2} -c "cd ${1};git pull" -m0;
else
    $4/mussh/mussh -H ${2} -c "${5}" -m0;
fi
