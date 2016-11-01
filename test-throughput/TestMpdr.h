#ifndef TEST_MPDR_H
#define TEST_MPDR_H

#define MSG_SIZE 18

typedef nx_struct mpdr_test_msg {
  nx_uint16_t seqno;
  nx_uint8_t data[MSG_SIZE];
} mpdr_test_msg_t;

#endif
