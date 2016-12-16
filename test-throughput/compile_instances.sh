#!/bin/bash

OLDIFS=$IFS
IFS=','
# for i in 1,57 2,52 3,77 4,35 5,67 6,70 7,69 8,49 #01
# for i in 5,14 6,70 #1,3 2,55 3,84 4,65 5,14 6,70 7,99 #02
# for i in 1,20,18 2,96,98 3,96,49 4,50,97 5,95,24 6,67,30 7,69,26 8,96,26
for i in 3,53,81 5,64,49 6,48,65 7,69,52 8,77,99 # 2paths-nocca-noack-02
do
  set -- $i
  # echo $1 and $2
  # echo ../ilp-solution/routes/single_$2_1.txt
  # echo ../ilp-solution/routes/dual_$2_1.txt

  # python generate_instance.py -f ../ilp-solution/routes/single_$2_$3.txt &&
  # make opal &&
  # mv build/opal/main.exe build/opal/test$1-1path-withcca-acked-04.exe

  python generate_instance.py -f ../ilp-solution/routes/dual_$2_$3.txt &&
  make opal &&
  mv build/opal/main.exe build/opal/test$1-2paths-nocca-noack-02.exe
done

IFS=$OLDIFS
