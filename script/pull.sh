#!/bin/bash
dsh -g $3 -M -c '
    if [ ! -d $2 ];then
        mkdir $2;
    fi
    cd $2;
    git pull
'
