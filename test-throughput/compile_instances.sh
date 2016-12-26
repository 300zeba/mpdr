#!/bin/bash

paths=1paths
cca=withcca
ack=withack

if [ "$paths" == "2paths" ]
then
  routes=routes
else
  routes=routes_ff
fi

OLDIFS=$IFS
IFS=','

for i in 5,62,19 6,94,26 7,52,25 8,98,26

do
  set -- $i

  python create_instance.py -f ../ilp-solution/$routes/dual_$2_$3.txt &&
  make opal &&
  mv build/opal/main.exe build/opal/test$1-$paths-$cca-$ack-$2-$3.exe
done

IFS=$OLDIFS

#Fix
