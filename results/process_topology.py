import subprocess
import glob
import re
import sys

def execute(command):
    p = subprocess.Popen(command, stdout=subprocess.PIPE)
    output, error = p.communicate()
    if error is None:
        return output
    return error

if len(sys.argv) > 1:
    lastFile = sys.argv[1]
else:
    command = ["ls"]
    output = execute(command)
    files = output.split()
    lastFile = files[len(files)-1]

outputFile = open("topology", "w")
command = ["tar", "-xvzf", lastFile]
output = execute(command)
files = glob.glob("result/node_*")
for fileName in files:
    inputFile = open(fileName, "r")
    for line in inputFile:
        p = re.compile(r"\[(.*)\]")
        s = p.search(line)
        if s:
            outputFile.write(line)
            #values = s.group()
            #print values

    inputFile.close()
outputFile.close()

command = ["rm", "-r", "result"]
output = execute(command)
