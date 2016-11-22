#include "TestMpdr.h"

#define NUM_TESTS 1
#define TEST_DELAY 10000
#define FINISH_TIME 20000
#define TEST_DURATION 30000
#define NUM_PATHS 1

#define TEST_NON_STOP 1
#define TEST_PERIODIC 0
#define NUM_MSGS 100
#define SEND_PERIOD 5

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

  uint8_t numPaths = NUM_PATHS;

  bool transmitting = FALSE;

  uint16_t sendCount = 0;
  uint16_t receivedCount = 0;
  uint8_t testCounter = 0;

  // Paths' cost: 27
  // Paths' len: 8
  uint8_t destinationNode = 9;
  uint8_t sourceNode = 1;
  uint8_t sourceRoutes[2][3] = {
    {5, 1, 1},
    {3, 2, 2},
  };
  uint8_t relayLength = 6;
  uint8_t relayNodes[6] = {5, 10, 3, 4, 6, 8, };
  uint8_t relayRoutes[6][3] = {
    {10, 2, 1},
    {9, 1, 2},
    {4, 1, 2},
    {6, 2, 1},
    {8, 1, 1},
    {9, 2, 2},
  };

  uint8_t getRelayIndex(uint8_t id) {
    uint8_t i;
    for (i = 0; i < relayLength; i++) {
      if (id == relayNodes[i]) {
        return i;
      }
    }
    return relayLength;
  }

  uint8_t getDestinationRadioChannel(uint8_t radio) {
    uint8_t i;
    for (i = 0; i < relayLength; i++) {
      if (relayRoutes[i][0] == destinationNode && relayRoutes[i][1] == radio) {
        return relayRoutes[i][2];
      }
    }
    return 0;
  }

  uint8_t getRelayRadioChannel(uint8_t radio) {
    uint8_t i;
    for (i = 0; i < relayLength; i++) {
      if (relayRoutes[i][0] == TOS_NODE_ID && relayRoutes[i][1] == radio) {
        return relayRoutes[i][2];
      }
    }
    for (i = 0; i < 2; i++) {
      if (sourceRoutes[i][0] == TOS_NODE_ID && sourceRoutes[i][1] == radio) {
        return sourceRoutes[i][2];
      }
    }
    return 0;
  }

  void initializeNode() {
    uint8_t relay_i;
    uint8_t radio;
    uint8_t channel1;
    uint8_t channel2;
    call SerialLogger.log(LOG_INITIALIZED, TOS_NODE_ID);
    if (TOS_NODE_ID == destinationNode) {
      call SerialLogger.log(LOG_DESTINATION_NODE, destinationNode);
      channel1 = getDestinationRadioChannel(1);
      channel2 = getDestinationRadioChannel(2);
      call MpdrRouting.setRadioChannel(1, channel1);
      call MpdrRouting.setRadioChannel(2, channel2);
      call FinishTimer.startPeriodicAt(TEST_DELAY + FINISH_TIME, TEST_DURATION);
    } else if (TOS_NODE_ID == sourceNode) {
      call SerialLogger.log(LOG_SOURCE_NODE, sourceNode);
      call MpdrRouting.addSendRoute(sourceNode, destinationNode,
                                    sourceRoutes[0][0], sourceRoutes[0][1],
                                    sourceRoutes[0][2]);
      call MpdrRouting.addSendRoute(sourceNode, destinationNode,
                                    sourceRoutes[1][0], sourceRoutes[1][1],
                                    sourceRoutes[1][2]);
      call MpdrRouting.setRadioChannel(sourceRoutes[0][1],
                                       sourceRoutes[0][2]);
      call MpdrRouting.setRadioChannel(sourceRoutes[1][1],
                                       sourceRoutes[1][2]);
      call TestTimer.startPeriodicAt(TEST_DELAY, TEST_DURATION);
      call FinishTimer.startPeriodicAt(TEST_DELAY + FINISH_TIME, TEST_DURATION);
    } else {
      relay_i = getRelayIndex(TOS_NODE_ID);
      if (relay_i < relayLength) {
        call SerialLogger.log(LOG_RELAY_NODE, relay_i);
        call MpdrRouting.addRoutingItem(sourceNode, destinationNode,
                                        relayRoutes[relay_i][0],
                                        relayRoutes[relay_i][1],
                                        relayRoutes[relay_i][2]);
        call MpdrRouting.setRadioChannel(relayRoutes[relay_i][1],
                                         relayRoutes[relay_i][2]);
        radio = (relayRoutes[relay_i][1] == 1)? 2: 1;
        channel2 = getRelayRadioChannel(radio);
        if (channel2 == 0) {
          call SerialLogger.log(LOG_GET_RELAY_CHANNEL_ERROR, channel2);
        }
        call MpdrRouting.setRadioChannel(radio, channel2);
        call FinishTimer.startPeriodicAt(TEST_DELAY + FINISH_TIME,
                                         TEST_DURATION);
      }
    }
  }

  void sendMessage() {
    uint8_t i;
    message_t* msg;
    mpdr_test_msg_t* payload;
    if (NUM_MSGS != 0 && sendCount >= NUM_MSGS) {
      transmitting = FALSE;
      return;
    }
    // call SerialLogger.log(LOG_SENDING_SEQNO, sendCount);
    msg = call MessagePool.get();
    if (msg == NULL) {
      call SerialLogger.log(LOG_MESSAGE_POOL_ERROR, 0);
      return;
    }
    payload = (mpdr_test_msg_t*) call MpdrPacket.getPayload(msg,
                                                       sizeof(mpdr_test_msg_t));
    payload->seqno = sendCount;
    sendCount++;
    for (i = 0; i < MSG_SIZE; i++) {
      payload->data[i] = i;
    }
    call MpdrPacket.setPayloadLength(msg, sizeof(mpdr_test_msg_t));
    call MpdrSend.send(destinationNode, msg, sizeof(mpdr_test_msg_t));
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

  event void MpdrSend.sendDone(message_t* msg, error_t error) {
    call MessagePool.put(msg);
    if (error != SUCCESS) {
      call SerialLogger.log(LOG_ERROR_MPDR_SEND_DONE, error);
    }
    if (TEST_NON_STOP) {
      sendMessage();
    }
  }

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
    sendMessage();
    if (numPaths == 2) {
      sendMessage();
    }
    if (TEST_PERIODIC) {
      call SendTimer.startPeriodic(SEND_PERIOD);
    }
  }

  event void SendTimer.fired() {
    if (transmitting) {
      sendMessage();
      if (numPaths == 2) {
        sendMessage();
      }
    }
  }

  event void FinishTimer.fired() {
    uint16_t data;
    call SerialLogger.log(LOG_TEST_NUMBER, testCounter);
    testCounter++;
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
    data = call MpdrStats.getMaxQueueSize1();
    call SerialLogger.log(LOG_MAX_QUEUE_1, data);
    data = call MpdrStats.getMaxQueueSize2();
    call SerialLogger.log(LOG_MAX_QUEUE_2, data);
    data = call MpdrStats.getDuplicated1();
    call SerialLogger.log(LOG_DUPLICATED_1, data);
    data = call MpdrStats.getDuplicated2();
    call SerialLogger.log(LOG_DUPLICATED_2, data);
    data = call MpdrPacket.maxPayloadLength();
    call SerialLogger.log(LOG_MAX_PAYLOAD_LENGTH, data);
    call MpdrStats.clear();
    sendCount = 0;
    if (NUM_TESTS > 0 && testCounter >= NUM_TESTS) {
      call TestTimer.stop();
      call FinishTimer.stop();
    }
  }

  event void MpdrRouting.pathsReady(am_addr_t destination) {}
}

//Fix
