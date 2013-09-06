#!/bin/bash 
$1/mussh/mussh -H ${2} -c "${3}" -m0;
echo $?;
rm ${2};
