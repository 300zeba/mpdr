#include "TestMpdr.h"

#define NUM_TESTS 1
#define TEST_DELAY 10000
#define FINISH_TIME 20000
#define TEST_DURATION 30000

#define NUM_MSGS 1000
#define SEND_PERIOD 2

#define INIT_TIME 10000

module TestMpdrC {
  uses {
    interface Boot;

    interface Timer<TMilli> as InitTimer;
    interface Timer<TMilli> as SendTimer;
    interface Timer<TMilli> as TestTimer;
    interface Timer<TMilli> as FinishTimer;

    interface SplitControl as SerialControl;
    interface SerialLogger;

    interface SplitControl as RadiosControl;

    interface StdControl as MpdrControl;
    interface MpdrRouting;
    interface AMSend as MpdrSend;
    interface Receive as MpdrReceive;
    interface Packet as MpdrPacket;
    interface MpdrStats;
    interface Pool<message_t> as MessagePool;
  }
}


implementation {

  bool transmitting = FALSE;

  message_t msgBuffer;

  uint16_t sendCount = 0;
  uint16_t receivedCount = 0;
  uint8_t testCounter = 0;

  /*// cost: 11
  // len: 4
  uint8_t numPaths = 2;
  uint8_t sourceNode = 77;
  uint8_t destinationNode = 2;
  uint8_t numHops = 4;
  uint8_t hops[4][4] = {
    {77, 78, 1, 1},
    {77, 81, 2, 2},
    {78, 2, 2, 1},
    {81, 2, 1, 2},
  };*/

  // cost: 34
  // len: 6
  uint8_t numPaths = 2;
  uint8_t sourceNode = 32;
  uint8_t destinationNode = 2;
  uint8_t numHops = 6;
  uint8_t hops[6][4] = {
    {32, 55, 1, 1},
    {32, 28, 2, 2},
    {55, 57, 2, 1},
    {57, 2, 1, 2},
    {28, 5, 1, 2},
    {5, 2, 2, 1},
  };

  bool isRelay() {
    uint8_t i;
    if (TOS_NODE_ID == sourceNode || TOS_NODE_ID == destinationNode) {
      return FALSE;
    }
    for (i = 0; i < numHops; i++) {
      if (TOS_NODE_ID == hops[i][0]) {
        return TRUE;
      }
    }
    return FALSE;
  }

  void initializeNode() {
    uint8_t i;
    uint8_t node;
    uint8_t next_hop;
    uint8_t radio;
    uint8_t channel;
    /*call SerialLogger.log(LOG_INITIALIZED, TOS_NODE_ID);*/
    for (i = 0; i < numHops; i++) {
      node = hops[i][0];
      next_hop = hops[i][1];
      radio = hops[i][2];
      channel = hops[i][3];
      if (TOS_NODE_ID == node || TOS_NODE_ID == next_hop) {
        call MpdrRouting.setRadioChannel(radio, channel);
      }
      if (TOS_NODE_ID == node && TOS_NODE_ID == sourceNode) {
        call MpdrRouting.addSendRoute(sourceNode, destinationNode,
                                      next_hop, radio, channel);
      }
      if (TOS_NODE_ID == node && TOS_NODE_ID != sourceNode) {
        call MpdrRouting.addRoutingItem(sourceNode, destinationNode,
                                        next_hop, radio, channel);
      }
    }
    if (TOS_NODE_ID == sourceNode) {
      call SerialLogger.log(LOG_SOURCE_NODE, sourceNode);
      call TestTimer.startPeriodicAt(TEST_DELAY, TEST_DURATION);
      call FinishTimer.startPeriodicAt(TEST_DELAY + FINISH_TIME, TEST_DURATION);
    } else if (TOS_NODE_ID == destinationNode) {
      call SerialLogger.log(LOG_DESTINATION_NODE, destinationNode);
      call FinishTimer.startPeriodicAt(TEST_DELAY + FINISH_TIME, TEST_DURATION);
    } else if (isRelay()){
      call SerialLogger.log(LOG_RELAY_NODE, TOS_NODE_ID);
      call FinishTimer.startPeriodicAt(TEST_DELAY + FINISH_TIME, TEST_DURATION);
    }
  }

  void sendMessage() {
    message_t* msg;
    mpdr_test_msg_t* payload;
    error_t result;
    uint8_t i;
    if (NUM_MSGS > 0 && sendCount >= NUM_MSGS) {
      transmitting = FALSE;
      return;
    }
    msg = &msgBuffer;
    payload = (mpdr_test_msg_t*) call MpdrPacket.getPayload(msg,
                                                       sizeof(mpdr_test_msg_t));
    payload->seqno = sendCount;
    for (i = 0; i < MSG_SIZE; i++) {
      payload->data[i] = i;
    }
    result = call MpdrSend.send(destinationNode, msg, sizeof(mpdr_test_msg_t));
    if (result == SUCCESS) {
      sendCount++;
    }
  }

  event void Boot.booted() {
    call SerialControl.start();
  }

  event void SerialControl.startDone(error_t err) {
    if (err != SUCCESS) {
      call SerialControl.start();
    } else {
      call RadiosControl.start();
    }
  }

  event void SerialControl.stopDone(error_t err) {}

  event void RadiosControl.startDone(error_t error) {
    if (error != SUCCESS) {
      call RadiosControl.start();
    } else {
      call MpdrControl.start();
      call MpdrRouting.setNumPaths(numPaths);
      call InitTimer.startOneShot(INIT_TIME);
    }
  }

  event void RadiosControl.stopDone(error_t error) {}

  event void MpdrSend.sendDone(message_t* msg, error_t error) {}

  event message_t* MpdrReceive.receive(message_t* msg, void* payload,
                                       uint8_t len) {
    uint8_t i;
    mpdr_test_msg_t* rcvd_payload = (mpdr_test_msg_t*) payload;
    receivedCount++;
    for (i = 0; i < MSG_SIZE; i++) {
      if (rcvd_payload->data[i] != i) {
        call SerialLogger.log(LOG_MSG_ERROR_I, i);
        call SerialLogger.log(LOG_MSG_ERROR_DATA, rcvd_payload->data[i]);
      }
    }
    return msg;
  }

  event void InitTimer.fired() {
    initializeNode();
  }

  event void TestTimer.fired() {
    transmitting = TRUE;
    call SendTimer.startPeriodic(SEND_PERIOD);
  }

  event void SendTimer.fired() {
    if (transmitting) {
      sendMessage();
    } else {
      call SendTimer.stop();
    }
  }

  event void FinishTimer.fired() {
    uint16_t data;
    call SerialLogger.log(LOG_TEST_NUMBER, testCounter);
    data = call MpdrStats.getReceivedRadio1();
    call SerialLogger.log(LOG_RECEIVED_RADIO_1, data);
    data = call MpdrStats.getReceivedRadio2();
    call SerialLogger.log(LOG_RECEIVED_RADIO_2, data);
    data = call MpdrStats.getSentRadio1();
    call SerialLogger.log(LOG_SENT_RADIO_1, data);
    data = call MpdrStats.getSentRadio2();
    call SerialLogger.log(LOG_SENT_RADIO_2, data);
    data = call MpdrStats.getTimeRadio1();
    call SerialLogger.log(LOG_RADIO_TIME_1, data);
    data = call MpdrStats.getTimeRadio2();
    call SerialLogger.log(LOG_RADIO_TIME_2, data);
    data = call MpdrStats.getRetransmissions1();
    call SerialLogger.log(LOG_RETRANSMISSIONS_1, data);
    data = call MpdrStats.getRetransmissions2();
    call SerialLogger.log(LOG_RETRANSMISSIONS_2, data);
    data = call MpdrStats.getDropped1();
    call SerialLogger.log(LOG_DROPPED_1, data);
    data = call MpdrStats.getDropped2();
    call SerialLogger.log(LOG_DROPPED_2, data);
    data = call MpdrStats.getMaxQueueSize();
    call SerialLogger.log(LOG_MAX_QUEUE, data);
    data = call MpdrStats.getDuplicated1();
    call SerialLogger.log(LOG_DUPLICATED_1, data);
    data = call MpdrStats.getDuplicated2();
    call SerialLogger.log(LOG_DUPLICATED_2, data);
    data = call MpdrStats.getEbusyRadio1();
    call SerialLogger.log(LOG_EBUSY_RADIO_1, data);
    data = call MpdrStats.getEbusyRadio2();
    call SerialLogger.log(LOG_EBUSY_RADIO_2, data);
    call MpdrStats.clear();
    sendCount = 0;
    receivedCount = 0;
    testCounter++;
    if (NUM_TESTS > 0 && testCounter >= NUM_TESTS) {
      call TestTimer.stop();
      call FinishTimer.stop();
    }
  }

  event void MpdrRouting.pathsReady(am_addr_t destination) {}
}
