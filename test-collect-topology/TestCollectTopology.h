#ifndef TEST_COLLECT_TOPOLOGY_H
#define TEST_COLLECT_TOPOLOGY_H

#include <AM.h>

#define CL_TEST 0xEE
#define MAX_NEIGHBORS 10
#define MAX_NODES 100
#define INVALID_ADDR TOS_BCAST_ADDR

typedef nx_struct topology_msg {
  nx_am_addr_t source;
  nx_am_addr_t neighbor;
  nx_uint8_t radio;
  nx_uint16_t quality;
} topology_msg_t;

typedef struct neighbor {
  am_addr_t destination;
  uint16_t link1_quality;
  uint16_t link2_quality;
} neighbor_t;

typedef struct my_node {
  am_addr_t address;
  uint8_t num_of_neighbors;
  neighbor_t neighbors[MAX_NEIGHBORS];
} my_node_t;

typedef struct network {
  uint8_t num_of_nodes;
  my_node_t nodes[MAX_NODES];
} network_t;

#endif
