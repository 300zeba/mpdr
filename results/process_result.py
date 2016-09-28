import subprocess
import glob
import re

LOG_CODES_FILE = "../mpdr/serial-logger/SerialLogger.h"
# LOG_CODES_FILE = "../test-two-radios/TestNetwork.h"

def execute(command):
    p = subprocess.Popen(command, stdout=subprocess.PIPE)
    output, error = p.communicate()
    if error is None:
        return output
    return error

command = ["ls"]
output = execute(command)
files = output.split()
lastFile = files[len(files)-1]
command = ["tar", "-xvzf", lastFile]
output = execute(command)
files = glob.glob("result/node_*")
logEntries = []
for fileName in files:
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
        for i in range(len(f)):
            f[i] = int(f[i])
        logEntry = []
        logEntry.append(f[0]*255**3 + f[1]*255**2 + f[2]*255 + f[3])
        logEntry.append(f[4]*255 + f[5])
        logEntry.append(f[6]*255 + f[7])
        logEntry.append(f[8]*255 + f[9])
        logEntries.append(logEntry)
    inputFile.close()
logEntries.sort(key=lambda x: x[1])
logCodesFile = open(LOG_CODES_FILE, "r")
logCodesText = logCodesFile.read()
p = re.compile(r"LOG\_(.*),")
logCodes = p.findall(logCodesText)
for logEntry in logEntries:
    logEntryText = ""
    # logEntryText += str(logEntry[0]) + "\t"
    logEntryText += str(logEntry[1]) + "\t"
    if logEntry[2] < len(logCodes):
        logEntryText += logCodes[logEntry[2]] + " "
    else:
        logEntryText += str(logEntry[2]) + " "
    logEntryText += str(logEntry[3]) + "\n"
    print logEntryText,
command = ["rm", "-r", "result"]
output = execute(command)