#!/bin/bash

# if (($# != 2)); then
#   echo "usage: ./calculate_route.sh <origin> <destination>"
#   exit 1
# fi
INIT=1472
END=1503
for i in $(seq $INIT $END)
do
  if [ ! -e result_$i.tgz ]
  then
    wget ftp://twonet.cs.uh.edu:8080/result_$i.tgz
  fi
  if [ -e result_$i.tgz ]
  then
    python process_result_2.py -f ../test-throughput/TestMpdr.h -i result_$i.tgz -o out_$i.txt &&
    python get_result_table.py -i out_$i.txt -o table_$i.txt
  else
    echo "File result_$i.tgz not downloaded!"
  fi
done
