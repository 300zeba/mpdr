#!/bin/bash

# if (($# != 2)); then
#   echo "usage: ./calculate_route.sh <origin> <destination>"
#   exit 1
# fi

for i in 30 78 84 9 12 14 94 96 98
do
  python create_data_file.py -i topology -o data.dat -s 1 -d $i &&
  glpsol -m shortest_single_path.mod -d data.dat -o ilp_output.txt &&
  python create_route_file.py -i ilp_output.txt -o single_route_$i.txt
done
