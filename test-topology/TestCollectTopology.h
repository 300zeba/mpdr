#ifndef TEST_COLLECT_TOPOLOGY_H
#define TEST_COLLECT_TOPOLOGY_H

#include <AM.h>

typedef nx_struct topology_msg {
  nx_am_addr_t source;
  nx_am_addr_t neighbor;
  nx_uint8_t radio;
  nx_uint16_t quality;
} topology_msg_t;

#endif
