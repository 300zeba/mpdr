import re
import networkx as nx
# import matplotlib.pyplot as plt
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
        quality = line[3];
        if link_radio == radio:
            links[(origin, destination)] = quality
    return links

def create_data_file(nodes, links1, links2, output, origin, destination):
    output.write("data;\nset N :=")
    for i in range(len(nodes)):
        if i == 0:
            output.write(" " + str(nodes[i]))
        else:
            output.write(", " + str(nodes[i]))
    output.write(";\nset O := " + str(origin) + ";\nset D := "+ str(destination) +";\nparam: A: c1 c2 :=\n")
    for key, value in links1.iteritems():
        w1 = 100 - value
        if w1 < 1:
            w1 = 1
        if w1 > 90:
            w1 = 1000
        w2 = 100
        if key in links2:
            w2 -= links2[key]
            if w2 < 1:
                w2 = 1
            if w2 > 90:
                w2 = 1000
        output.write(str(key[0]) + "," + str(key[1]) + " " + str(w1) + " " + str(w2) + "\n")
    for key, value in links2.iteritems():
        if key in links1:
            continue
        w1 = 1000
        w2 = 100 - value
        if w2 < 1:
            w2 = 1
        if w2 > 90:
            w2 = 1000
        output.write(str(key[0]) + "," + str(key[1]) + " " + str(w1) + " " + str(w2) + "\n")
    output.write(";\nend;")

def grid_layout(G, width, height):
    layout = {}
    for node in G.nodes():
        layout[node] = [(node-1) % width, 10-(node-1) // height]
    return layout


def create_nx_digraph(nodes, links, filename):
    G = nx.DiGraph()
    G.add_nodes_from(nodes)
    G.add_edges_from(links.keys())
    for key, value in links.iteritems():
        G[key[0]][key[1]]['weight'] = (100-value) if (100-value) >= 1 else 1
    isolates = nx.isolates(G)
    G.remove_nodes_from(isolates)
    # pos = grid_layout(G, 10, 10)
    pos = nx.spring_layout(G)
    nx.draw_networkx_nodes(G, pos)
    nx.draw_networkx_edges(G, pos, arrows=False)
    nx.draw_networkx_labels(G, pos)
    # plt.savefig(filename)
    # plt.show()

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
    create_data_file(nodes, links1, links2, outputFile, source, destination)
    both_links = get_link_intersection(links1, links2)
    # create_nx_digraph(nodes, both_links, "both_links.png")

if __name__ == "__main__":
    main()
