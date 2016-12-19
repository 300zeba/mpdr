#!/bin/bash

OLDIFS=$IFS
IFS=','

# for i in 5,91,25 6,84,9 7,5,25 8,30,25
# for i in 6,84,9 7,5,25 8,30,25
# for i in 5,47,93 6,49,63 7,28,25 8,98,27
for i in 5,83,9 6,55,25 7,3,25 8,26,25
# for i in 5,81,9 6,49,65 7,46,34 8,17,52 # old
# for i in 5,22,93 6,5,97 7,27,25 8,46,27
# for i in 7,3,25
do
  set -- $i

  python generate_instance.py -f ../ilp-solution/routes_ff/dual_$2_$3.txt &&
  make opal &&
  mv build/opal/main.exe build/opal/test$1-1path-nocca-nohack-$2-$3.exe
done

IFS=$OLDIFS
