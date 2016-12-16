import subprocess
import glob
import re
import sys
import argparse

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("-i", "--input-file", nargs="?",
                        type=argparse.FileType("r"), required=True)
    parser.add_argument("-o", "--output-file", nargs="?",
                        type=argparse.FileType("w"), default=sys.stdout)
    args = parser.parse_args()

    inputFile = args.input_file
    outputFile = args.output_file

    sent = []
    received = []
    time = []

    source = 0
    destination = 0

    for line in inputFile:
        split_values = line.split()
        if len(split_values) != 3:
            continue
        node = split_values[0]
        description = split_values[1]
        value = split_values[2]
        if description == "SOURCE_NODE":
            source = node
        if description == "DESTINATION_NODE":
            destination = node
        if node == source:
            if description == "SENT_TOTAL":
                sent.append(value)
        if node == destination:
            if description == "RECEIVED_TOTAL":
                received.append(value)
            if description == "TIME_TOTAL":
                time.append(value)
    while len(sent) < 10:
        sent.append("error")
    while len(received) < 10:
        received.append("error")
    while len(time) < 10:
        time.append("error")
    for i in range(10):
        outputFile.write(sent[i] + "\t" + received[i] + "\t" + time[i] + "\n")

if __name__ == "__main__":
    main()
