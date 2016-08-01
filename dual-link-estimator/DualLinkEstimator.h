#ifndef DUAL_LINK_ESITIMATOR_H
#define DUAL_LINK_ESITIMATOR_H

#define MAX_NEIGHBOR_TABLE_SIZE 10

typedef nx_struct estimator_msg {
  nx_am_addr_t source;
  nx_uint16_t seqno;
} estimator_msg_t;

typedef struct dual_neighbor_table_entry {
  am_addr_t address;
  uint16_t received;
  uint16_t sent;
} dual_neighbor_table_entry_t;

typedef struct neighbor_table {
  uint8_t size;
  dual_neighbor_table_entry_t neighbors[MAX_NEIGHBOR_TABLE_SIZE];
} neighbor_table_t;

#endif
