#!/bin/bash

if (($# != 2)); then
  echo "usage: ./get_result_tables.sh <FIRST> <LAST>"
  exit 1
fi

INIT=$1
END=$2
for i in $(seq $INIT $END)
do
  if [ ! -e testbed/result_$i.tgz ]
  then
    wget ftp://twonet.cs.uh.edu:8080/result_$i.tgz
    mv result_$i.tgz testbed/result_$i.tgz
  fi
  if [ -e testbed/result_$i.tgz ]
  then
    python process_result_2.py -f ../test-throughput/TestMpdr.h -i testbed/result_$i.tgz -o outputs/out_$i.txt &&
    python get_result_table.py -i outputs/out_$i.txt -o tables/table_$i.txt
  else
    echo "File result_$i.tgz not downloaded!"
  fi
done
