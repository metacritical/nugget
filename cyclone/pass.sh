#!/bin/bash
#echo "(display ((lambda (x) (* x x)) 10))" | huski compiler.scm > 100.c && gcc 100.c -o 100

CC=./compiler
#CC=huski compiler.scm

if [[ $# -eq 0 ]] ; then
    echo 'usage: pass.sh file.scm'
    exit 0
fi

$CC compiler.scm < $1
