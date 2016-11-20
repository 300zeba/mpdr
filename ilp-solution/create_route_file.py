import re
import argparse
import pprint as pp

def to_dict(string_tuples):
    int_tuples = []
    for item in string_tuples:
        int_tuples.append({"radio": int(item[0]),
                           "source": int(item[1]),
                           "destination": int(item[2])})
    return int_tuples

def get_source(links):
    for i in range(len(links)):
        found = False
        for j in range(len(links)):
            if links[i]["source"] == links[j]["destination"]:
                found = True
        if not found:
            return links[i]["source"]
    return None

def get_destination(links):
    for i in range(len(links)):
        found = False
        for j in range(len(links)):
            if links[i]["destination"] == links[j]["source"]:
                found = True
        if not found:
            return links[i]["destination"]
    return None

def get_next_hop(links, source, first=None):
    for link in links:
        if link["source"] == source:
            if first:
                if link["radio"] == first:
                    return link["destination"]
            else:
                return link["destination"]
    return None

def get_link(links, source=None, destination=None, radio=None):
    for link in links:
        match = True
        if source and source != link["source"]:
            match = False
        if destination and destination != link["destination"]:
            match = False
        if radio and radio != link["radio"]:
            match = False
        if match:
            return link
    return None

def add_channel(links, source, destination):
    source_routes = []
    relay_routes = []
    current_node = get_link(links, source=source, radio=1)
    if current_node:
        source_routes.append(current_node)
        next_hop = current_node["destination"]
        channel = 1
        count = 0
        while next_hop != destination:
            current_node["channel"] = channel
            count += 1
            if count % 2 == 0:
                channel = 1 if channel == 2 else 2
            current_node = get_link(links, source=next_hop)
            relay_routes.append(current_node)
            next_hop = current_node["destination"]
        current_node["channel"] = channel
    current_node = get_link(links, source=source, radio=2)
    if current_node:
        source_routes.append(current_node)
        next_hop = current_node["destination"]
        channel = 2
        count = 0
        while next_hop != destination:
            current_node["channel"] = channel
            count += 1
            if count % 2 == 0:
                channel = 1 if channel == 2 else 2
            current_node = get_link(links, source=next_hop)
            relay_routes.append(current_node)
            next_hop = current_node["destination"]
        current_node["channel"] = channel
    return source_routes, relay_routes


def get_routes(inputFile, outputFile):
    text = inputFile.read()
    matches = re.search(r"obj = (\d+)", text)
    value = matches.group(1)
    matches = re.findall(r"x(\d)\[(\d+),(\d+)\] *\* *1", text)
    links = to_dict(matches)
    source = get_source(links)
    destination = get_destination(links)
    source_routes, relay_routes = add_channel(links, source, destination)
    paths_len = len(source_routes) + len(relay_routes)
    outputText =  "  // Paths' cost: " + value + "\n"
    outputText += "  // Paths' len: " + str(paths_len) + "\n"
    outputText += "  uint8_t destinationNode = " + str(destination) + ";\n"
    outputText += "  uint8_t sourceNode = " + str(source) + ";\n"
    outputText += "  uint8_t sourceRoutes[2][3] = {\n"
    for link in source_routes:
        outputText += "    {" + str(link["destination"]) + ", "
        outputText +=           str(link["radio"]) + ", "
        outputText +=           str(link["channel"]) + "},\n"
    outputText += "  };\n"
    outputText += "  uint8_t relayLength = " + str(len(relay_routes)) + ";\n"
    outputText += "  uint8_t relayNodes[" + str(len(relay_routes)) + "] = {"
    for link in relay_routes:
        outputText += str(link["source"]) + ", "
    outputText += "};\n"
    outputText += "  uint8_t relayRoutes[" + str(len(relay_routes)) + "][3] = {\n"
    for link in relay_routes:
        outputText += "    {" + str(link["destination"]) + ", "
        outputText +=           str(link["radio"]) + ", "
        outputText +=           str(link["channel"]) + "},\n"
    outputText += "  };\n"
    print outputText
    outputFile.write(outputText);

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("-i", "--input-file", nargs="?",
                        type=argparse.FileType("r"), required=True)
    parser.add_argument("-o", "--output-file", nargs="?",
                        type=argparse.FileType("w"), required=True)
    args = parser.parse_args()
    inputFile = args.input_file
    outputFile = args.output_file
    get_routes(inputFile, outputFile);

if __name__ == "__main__":
    main()
