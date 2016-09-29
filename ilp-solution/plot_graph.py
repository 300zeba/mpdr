import networkx as nx
import matplotlib.pyplot as plt

# G = nx.DiGraph()
# G.add_node(1)
# G.add_node(2)
# G.add_node(3)
# G.add_edge(1,2, weight=5)
# G.add_edge(1,3, weight=5)

G = nx.lollipop_graph(5,5)

print G.nodes()
print G.edges()

nx.spring_layout(G)
nx.draw(G)
plt.show()
# plt.savefig("graph.png")
