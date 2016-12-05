import re
import argparse
import pprint as pp
import glob
import sys

def get_min_routes(pattern):
    files = glob.glob(pattern)
    min_routes = {}
    for fileName in files:
        inputFile = open(fileName, "r")
        text = inputFile.read()
        match = re.search(r"cost: (\d+)", text)
        if match:
            value = match.group(1)
            cost = int(value)
        match = re.search(r"len: (\d+)", text)
        if match:
            value = match.group(1)
            length = int(value)
        if length not in min_routes:
            min_routes[length] = (fileName, cost)
        else:
            if min_routes[length][1] > cost:
                min_routes[length] = (fileName, cost)
    return min_routes

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("-o", "--output-file", nargs="?",
                        type=argparse.FileType("w"), default=sys.stdout)
    args = parser.parse_args()
    outputFile = args.output_file
    min_dual = get_min_routes("routes/dual_*_1.txt")
    pp.pprint(min_dual)
    # min_single = get_min_routes("routes/single_*.txt")
    # pp.pprint(min_single)



if __name__ == "__main__":
    main()
