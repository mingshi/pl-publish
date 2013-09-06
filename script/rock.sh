#!/bin/sh
if [ -z "$4" ];then
    $1/mussh/mussh -H ${3} -c "cd ${2};git log|grep 'commit' |sed -n '2p'|awk '{print \$2}'|xargs git reset --hard" -m0
else
    $1/mussh/mussh -H ${3} -c "cd ${2};git reset --hard ${4}" -m0
fi
