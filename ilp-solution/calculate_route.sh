#!/bin/bash

if (($# != 2)); then
  echo "usage: ./calculate_route.sh <origin> <destination>"
  exit 1
fi

python create_data_file.py -i topology -o data.dat -s $1 -d $2 &&
glpsol -m shortest_paths_with_parity.mod -d data.dat -o ilp_output.txt &&
python create_route_file.py -i ilp_output.txt -o route.txt
