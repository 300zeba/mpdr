#!/bin/bash

# if (($# != 2)); then
#   echo "usage: ./calculate_route.sh <origin> <destination>"
#   exit 1
# fi
INIT=1464
END=1471
for i in $(seq $INIT $END)
do
  python process_result_2.py -f ../test-throughput/TestMpdr.h -i result_$i.tgz -o out_$i.txt &&
  python get_result_table.py -i out_$i.txt -o table_$i.txt
done
