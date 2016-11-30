import re
import argparse

def read_log_file(file, format):
    """
        Reads the input file containing the values sent to the serial port
        between brackets [], separated by comma, and returns a list with integer
        values. The format is a list of strings with names of types, and accepts
        "uint8_t", "uint16_t" or "uint32_t".
    """
    log = []
    for line in file:
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
        l = []
        for type in format:
            n1 = 0
            n2 = 0
            n3 = 0
            n4 = 0
            if type == "uint8_t":
                n1 = f.pop(0)
            elif type == "uint16_t":
                n2 = f.pop(0)
                n1 = f.pop(0)
            elif type == "uint32_t":
                n4 = f.pop(0)
                n3 = f.pop(0)
                n2 = f.pop(0)
                n1 = f.pop(0)
            l.append(n4*255**3 + n3*255**2 + n2*255 + n1)
        log.append(l)
    return log

def get_nodes(log):
    nodes = []
    for line in log:
        if line[0] not in nodes:
            nodes.append(line[0])
        if line[1] not in nodes:
            nodes.append(line[1])
    return nodes

def get_links(log, radio):
    links = {}
    for line in log:
        destination = line[0]
        origin = line[1]
        link_radio = line[2]
        quality = 100 - line[3]
        if quality < 1:
            quality = 1;
        if quality > 90:
            quality = 10000
        if link_radio == radio:
            links[(origin, destination)] = quality
    return links

def merge_links(links1, links2):
    merged = {}
    for key, value in links1.iteritems():
        merged[key] = [value, 10000]
    for key, value in links2.iteritems():
        if key in merged:
            merged[key][1] = value
        else:
            merged[key] = [10000, value]
    return merged

def create_data_file(nodes, merged, output, origin, destination):
    output.write("data;\nset N :=")
    nodes.sort()
    for i in range(len(nodes)):
        if i == 0:
            output.write(" " + str(nodes[i]))
        else:
            output.write(", " + str(nodes[i]))
    output.write(";\nset O := " + str(origin) + ";\n")
    output.write("set D := "+ str(destination) +";\nparam: A: c1 c2 :=\n")
    keys = merged.keys()
    keys.sort(key=lambda x: (x[0], x[1]))
    for key in keys:
        value = merged[key]
        output.write(str(key[0]) + "," + str(key[1]) + " ")
        output.write(str(value[0]) + " " + str(value[1]) + "\n")
    output.write(";\nend;")

def grid_layout(G, width, height):
    layout = {}
    for node in G.nodes():
        layout[node] = [(node-1) % width, 10-(node-1) // height]
    return layout

def get_link_difference(links1, links2):
    link_diff = {}
    for key, value in links1.iteritems():
        if key not in links2:
            link_diff[key] = value
    return link_diff

def get_link_intersection(links1, links2):
    link_inter = {}
    for key, value in links1.iteritems():
        if key in links2:
            if value > 70 and links2[key] > 70:
                link_inter[key] = value
    return link_inter;

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("-i", "--input-file", nargs="?",
                        type=argparse.FileType("r"), required=True)
    parser.add_argument("-o", "--output-file", nargs="?",
                        type=argparse.FileType("w"), required=True)
    parser.add_argument("-s", "--source", type=int, default=1)
    parser.add_argument("-d", "--destination", type=int, default=100)
    args = parser.parse_args()
    inputFile = args.input_file
    outputFile = args.output_file
    source = args.source
    destination = args.destination
    log = read_log_file(inputFile, ["uint16_t", "uint16_t", "uint8_t", "uint16_t"])
    nodes = get_nodes(log)
    links1 = get_links(log, 1)
    links2 = get_links(log, 2)
    merged = merge_links(links1, links2)
    create_data_file(nodes, merged, outputFile, source, destination)
    both_links = get_link_intersection(links1, links2)

if __name__ == "__main__":
    main()
