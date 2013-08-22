#!/bin/sh
if [ -z "$3" ];then
    mussh/mussh -H ${2} -c "cd ${1};git log|grep 'commit' |sed -n '2p'|awk '{print \$2}'|xargs git reset --hard" -m0
else
    mussh/mussh -H ${2} -c "cd ${1};git reset --hard ${3}" -m0
fi
