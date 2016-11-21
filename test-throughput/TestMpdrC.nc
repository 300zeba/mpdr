#include "TestMpdr.h"
#include "../serial-logger/SerialLogger.h"

#define NUM_TESTS 1
#define TEST_DELAY 10000
#define FINISH_TIME 20000
#define TEST_DURATION 30000
#define NUM_PATHS 2

#define TEST_NON_STOP 1
#define TEST_PERIODIC 0
#define NUM_MSGS 1000
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

  bool transmitting = FALSE;

  uint16_t sendCount = 0;
  uint16_t receivedCount = 0;
  uint16_t messageSize;

  uint32_t startTime = 0;
  uint32_t endTime = 0;
  uint32_t elapsedTime = 0;

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
    uint8_t relayIndex;
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
      relayIndex = getRelayIndex(TOS_NODE_ID);
      if (relayIndex < relayLength) {
        call SerialLogger.log(LOG_RELAY_NODE, relayIndex);
        call MpdrRouting.addRoutingItem(sourceNode, destinationNode,
                                        relayRoutes[relayIndex][0],
                                        relayRoutes[relayIndex][1],
                                        relayRoutes[relayIndex][2]);
        call MpdrRouting.setRadioChannel(relayRoutes[relayIndex][1],
                                         relayRoutes[relayIndex][2]);
        radio = (relayRoutes[relayIndex][1] == 1)? 2: 1;
        channel2 = getRelayRadioChannel(radio);
        if (channel2 == 0) {
          call SerialLogger.log(LOG_GET_RELAY_CHANNEL_ERROR, channel2);
        }
        call MpdrRouting.setRadioChannel(radio, channel2);
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
    endTime = call FinishTimer.getNow();
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
      call MpdrRouting.setNumPaths(NUM_PATHS);
      call InitTimer.startOneShot(INIT_TIME);
    }
  }

  event void RadiosControl.stopDone(error_t error) {}

  event void MpdrSend.sendDone(message_t* msg, error_t error) {
    // mpdr_test_msg_t* payload;
    call MessagePool.put(msg);
    if (error == SUCCESS) {
      // payload = (mpdr_test_msg_t*) call MpdrPacket.getPayload(msg,
      //                                                  sizeof(mpdr_test_msg_t));
      // call SerialLogger.log(LOG_MPDR_SEND_DONE, payload->seqno);
    } else {
      call SerialLogger.log(LOG_ERROR_MPDR_SEND_DONE, error);
    }
    if (TEST_NON_STOP) {
      sendMessage();
    }
  }

  event message_t* MpdrReceive.receive(message_t* msg, void* payload,
                                       uint8_t len) {
    uint8_t i;
    mpdr_test_msg_t* rcvdPayload = (mpdr_test_msg_t*) payload;
    receivedCount++;
    // call SerialLogger.log(LOG_MPDR_RECEIVE, rcvdPayload->seqno);
    for (i = 0; i < MSG_SIZE; i++) {
      if (rcvdPayload->data[i] != i) {
        call SerialLogger.log(LOG_MSG_ERROR_I, i);
        call SerialLogger.log(LOG_MSG_ERROR_DATA, rcvdPayload->data[i]);
      }
    }
    if (startTime == 0) {
      startTime = call FinishTimer.getNow();
    }
    endTime = call FinishTimer.getNow();
    return msg;
  }

  event void InitTimer.fired() {
    initializeNode();
  }

  event void TestTimer.fired() {
    transmitting = TRUE;
    startTime = call FinishTimer.getNow();
    // call SerialLogger.log(LOG_TEST_TIMER_FIRED, startTime);
    sendMessage();
    if (NUM_PATHS == 2) {
      sendMessage();
    }
    if (TEST_PERIODIC) {
      call SendTimer.startPeriodic(SEND_PERIOD);
    }
  }

  event void SendTimer.fired() {
    if (transmitting) {
      sendMessage();
      if (NUM_PATHS == 2) {
        sendMessage();
      }
    }
  }

  event void FinishTimer.fired() {
    uint32_t radioTime;
    call SerialLogger.log(LOG_TEST_NUMBER, testCounter);
    testCounter++;
    if (TOS_NODE_ID == sourceNode) {
      uint16_t radio1 = call MpdrStats.getSentRadio1();
      uint16_t radio2 = call MpdrStats.getSentRadio2();
      call SerialLogger.log(LOG_SENT_RADIO_1, radio1);
      call SerialLogger.log(LOG_SENT_RADIO_2, radio2);
    } else if (TOS_NODE_ID == destinationNode) {
      uint16_t radio1 = call MpdrStats.getReceivedRadio1();
      uint16_t radio2 = call MpdrStats.getReceivedRadio2();
      call SerialLogger.log(LOG_RECEIVED_RADIO_1, radio1);
      call SerialLogger.log(LOG_RECEIVED_RADIO_2, radio2);
    }
    elapsedTime = endTime - startTime;
    call SerialLogger.log(LOG_ELAPSED_TIME, elapsedTime);
    radioTime = call MpdrStats.getTimeRadio1();
    call SerialLogger.log(LOG_RADIO_1_TIME, radioTime);
    radioTime = call MpdrStats.getTimeRadio2();
    call SerialLogger.log(LOG_RADIO_2_TIME, radioTime);
    call SerialLogger.log(LOG_MESSAGE_SIZE, sizeof(message_t));
    call SerialLogger.log(LOG_PAYLOAD_SIZE, sizeof(mpdr_test_msg_t));
    call MpdrStats.clear();
    startTime = 0;
    if (NUM_TESTS > 0 && testCounter >= NUM_TESTS) {
      call TestTimer.stop();
      call FinishTimer.stop();
    }
  }

  event void MpdrRouting.pathsReady(am_addr_t destination) {}
}

//Fix
