import re
import networkx as nx
import matplotlib.pyplot as plt
import argparse
import pprint as pp
import glob
import sys

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("-o", "--output-file", nargs="?",
                        type=argparse.FileType("w"), default=sys.stdout)
    args = parser.parse_args()
    outputFile = args.output_file
    files = glob.glob("dual_route_*")
    min_routes = {}
    for fileName in files:
        inputFile = open(fileName, "r")
        text = inputFile.read()
        match = re.search(r"cost: (\d+)", text)
        value = match.group(1)
        cost = int(value)
        match = re.search(r"len: (\d+)", text)
        value = match.group(1)
        length = int(value)
        if length not in min_routes:
            min_routes[length] = (fileName, cost)
        else:
            if min_routes[length][1] > cost:
                min_routes[length] = (fileName, cost)
    pp.pprint(min_routes)



if __name__ == "__main__":
    main()
