import re
import argparse
import pprint as pp
import glob
import sys

def get_min_routes(pattern):
    files = glob.glob(pattern)
    all_routes = {}
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
        if length not in all_routes:
            all_routes[length] = [(fileName, cost)]
        else:
            all_routes[length].append((fileName, cost))
    min_routes = {}
    for size, routes in all_routes.iteritems():
        routes.sort(key=lambda x:x[1])
        min_routes[size] = routes[5:10]
    return min_routes

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("-o", "--output-file", nargs="?",
                        type=argparse.FileType("w"), default=sys.stdout)
    args = parser.parse_args()
    outputFile = args.output_file
    min_dual = get_min_routes("routes/dual_*.txt")
    pp.pprint(min_dual)

if __name__ == "__main__":
    main()
