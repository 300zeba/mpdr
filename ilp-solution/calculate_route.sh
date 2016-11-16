#!/bin/bash

python create_data_file.py -i topology -o data.dat -s $1 -d $2
glpsol -m shortest_paths_with_parity.mod -d data.dat -o output.txt
python create_route_file.py -i output.txt -o route.txt
