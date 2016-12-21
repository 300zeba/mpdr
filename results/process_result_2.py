import subprocess
import glob
import re
import sys
import argparse

def execute(command):
    p = subprocess.Popen(command, stdout=subprocess.PIPE)
    output, error = p.communicate()
    if error is None:
        return output
    return error

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("-f", "--log-codes-file", nargs="?",
                        type=argparse.FileType("r"), required=True)
    parser.add_argument("-o", "--output-file", nargs="?",
                        type=argparse.FileType("w"))
    parser.add_argument("-i", "--input-file")
    args = parser.parse_args()

    if args.input_file is not None:
        lastFile = args.input_file
    else:
        command = ["ls", "testbed/*"]
        output = execute(command)
        files = output.split()
        lastFile = files[len(files)-1]

    command = ["tar", "-xvzf", lastFile]
    output = execute(command)
    files = glob.glob("result/node_*")
    logEntries = []
    for fileName in files:
        nodeid = int(fileName[12:])
        inputFile = open(fileName, "r")
        for line in inputFile:
            p = re.compile(r"\[(.*)\]")
            s = p.search(line);
            values = ""
            if s:
                values = s.group()
            else:
                continue
            p = re.compile(r"\d+")
            f = p.findall(values)
            if len(f) != 4:
                continue
            for i in range(len(f)):
                f[i] = int(f[i])
            logEntry = []
            logEntry.append(nodeid)
            logEntry.append(f[0]*255 + f[1])
            logEntry.append(f[2]*255 + f[3])
            logEntries.append(logEntry)
        inputFile.close()
    logEntries.sort(key=lambda x: x[0])
    logCodesFile = args.log_codes_file
    logCodesText = logCodesFile.read()
    p = re.compile(r"LOG\_(.*),")
    logCodes = p.findall(logCodesText)
    lastNode = 0
    for logEntry in logEntries:
        logEntryText = ""
        if logEntry[0] != lastNode:
            lastNode = logEntry[0]
            logEntryText += "\n"
        logEntryText += str(logEntry[0]) + "\t"
        if logEntry[1] < len(logCodes):
            logEntryText += logCodes[logEntry[1]] + " "
        else:
            logEntryText += str(logEntry[1]) + " "
        logEntryText += str(logEntry[2]) + "\n"
        print logEntryText,
        if args.output_file:
            args.output_file.write(logEntryText)
    command = ["rm", "-r", "result"]
    output = execute(command)

if __name__ == "__main__":
    main()
