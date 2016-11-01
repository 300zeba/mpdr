#include "TestMpdr.h"
#include "../serial-logger/SerialLogger.h"

#define ROOT_NODE 2
#define NUM_HOPS 3

module TestMpdrC {
  uses {
    interface Boot;

    interface Timer<TMilli> as InitTimer;
    interface Timer<TMilli> as NodeTimer;
    interface Timer<TMilli> as RootTimer;
    interface Timer<TMilli> as SendTimer;

    interface SplitControl as SerialControl;
    interface SerialLogger;

    interface SplitControl as RadiosControl;

    interface StdControl as MpdrControl;
    interface MpdrRouting;
    interface AMSend as MpdrSend;
    interface Receive as MpdrReceive;
    interface Packet as MpdrPacket;
  }
}


implementation {

  am_addr_t sendTo = 1;
  message_t msgBuffer;
  bool transmitting = FALSE;
  bool sendBusy = FALSE;

  uint16_t receivedCount = 0;
  uint16_t totalCount = 0;
  uint16_t sendBusyCount = 0;
  uint32_t timeElapsed;
  uint8_t messageSize;
  uint16_t throughput;

  enum {
    SEND_PATH_1,
    SEND_PATH_2,
    RESEND_PATHS,
    SEND_STATISTICS,
  };

  uint8_t rootAction;
  uint8_t numPaths = 2;

  // Routes:
  // 01 -> 05 -> 10 -> 31 -> 12 -> 14 -> 93 -> 100
  // 01 -> 60 -> 62 -> 64 -> 67 -> 100
  uint8_t destinationNode = 100;
  uint8_t sourceNode = 1;
  uint8_t sourceRoutes[2][3] = {
    {5, 1, 1},
    {60, 2, 2}
  };
  uint8_t relayLength = 10;
  uint8_t relayNodes[10] = {5, 10, 31, 12, 14, 93, 60, 62, 64, 67};
  uint8_t relayRoutes[10][3] = {
    {10, 2, 1},
    {31, 1, 2},
    {12, 2, 2},
    {14, 1, 1},
    {93, 2, 1},
    {100, 1, 2},

    {62, 1, 2},
    {64, 2, 1},
    {67, 1, 1},
    {100, 2, 2},
  };

  /*uint8_t destinationNode = 100;
  uint8_t sourceNode = 1;
  uint8_t sourceRoutes[2][3] = {
    {76, 1, 1},
    {6, 2, 2}
  };
  uint8_t relayLength = 8;
  uint8_t relayNodes[8] = {76, 6, 27, 13, 34, 95, 12, 20};
  uint8_t relayRoutes[8][3] = {
    {27, 2, 1},
    {13, 1, 2},
    {34, 1, 2},
    {95, 2, 1},
    {12, 2, 2},
    {100, 1, 1},
    {20, 1, 1},
    {100, 2, 1}
  };*/

  /*uint8_t destinationNode = 100;
  uint8_t sourceNode = 1;
  uint8_t sourceRoutes[2][3] = {
    {35, 1, 1},
    {6, 2, 2}
  };
  uint8_t relayLength = 6;
  uint8_t relayNodes[6] = {35, 6, 12, 13, 20, 95};
  uint8_t relayRoutes[6][3] = {
    {12, 2, 1},
    {13, 1, 2},
    {20, 1, 2},
    {95, 2, 1},
    {100, 2, 2},
    {100, 1, 1}
  };*/

  /*uint8_t destinationNode = 2;
  uint8_t sourceNode = 79;
  uint8_t sourceRoutes[2][3] = {
    {85, 1, 2},
    {29, 2, 1}
  };
  uint8_t relayLength = 4;
  uint8_t relayNodes[4] = {56, 85, 7, 29};
  uint8_t relayRoutes[4][3] = {
    {2, 1, 1},
    {56, 2, 1},
    {2, 2, 2},
    {7, 1, 2}
  };*/

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
      call InitTimer.startOneShot(20000);
    }
  }

  event void RadiosControl.stopDone(error_t error) {}

  event void InitTimer.fired() {
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
      // call RootTimer.startOneShot(60000);
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
      call SendTimer.startOneShot(10000);
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

  event void RootTimer.fired() {
      call SerialLogger.log(LOG_RECEIVED_COUNT, receivedCount);
      call SerialLogger.log(LOG_TOTAL_COUNT, totalCount);
      //call SerialLogger.log(LOG_MESSAGE_SIZE, messageSize);
      //call SerialLogger.log(LOG_THROUGHPUT, throughput);
  }

  event void NodeTimer.fired() {
    transmitting = FALSE;
    call SerialLogger.log(LOG_TOTAL_SENT, totalCount);
  }

  void sendMessage() {
    uint8_t i;
    message_t* msg;
    mpdr_test_msg_t* payload;
    error_t error;
    msg = &msgBuffer;
    payload = (mpdr_test_msg_t*) call MpdrPacket.getPayload(msg,
                                                       sizeof(mpdr_test_msg_t));
    payload->seqno = totalCount;
    for (i = 0; i < MSG_SIZE; i++) {
      payload->data[i] = i;
    }
    call MpdrPacket.setPayloadLength(msg, sizeof(mpdr_test_msg_t));
    error = call MpdrSend.send(sendTo, msg, sizeof(mpdr_test_msg_t));
    if (error != SUCCESS) {
      call SerialLogger.log(LOG_ERROR_MPDR_SEND, error);
    }
  }

  event void SendTimer.fired() {
    if (call SendTimer.isOneShot()) {
      call SerialLogger.log(LOG_START_SENDING, 0);
      sendTo = destinationNode;
      transmitting = TRUE;
      call SendTimer.startPeriodic(1000);
    }
    if (totalCount > 99) {
      transmitting = FALSE;
    }
    if (transmitting) {
      sendMessage();
    }
  }

  event void MpdrSend.sendDone(message_t* msg, error_t error) {
    mpdr_test_msg_t* payload;
    if (error == SUCCESS) {
      totalCount++;
      payload = (mpdr_test_msg_t*) call MpdrPacket.getPayload(msg,
                                                       sizeof(mpdr_test_msg_t));
      call SerialLogger.log(LOG_MPDR_SEND_DONE, payload->seqno);
    } else {
      call SerialLogger.log(LOG_ERROR_MPDR_SEND_DONE, error);
    }
  }

  event message_t* MpdrReceive.receive(message_t* msg, void* payload,
                                       uint8_t len) {
    uint8_t i;
    mpdr_test_msg_t* rcvdPayload = (mpdr_test_msg_t*) payload;
    receivedCount++;
    totalCount = rcvdPayload->seqno;
    call SerialLogger.log(LOG_MPDR_RECEIVE, rcvdPayload->seqno);
    for (i = 0; i < MSG_SIZE; i++) {
      if (rcvdPayload->data[i] != i) {
        call SerialLogger.log(LOG_MSG_ERROR_I, i);
        call SerialLogger.log(LOG_MSG_ERROR_DATA, rcvdPayload->data[i]);
      }
    }
    return msg;
  }

  event void MpdrRouting.pathsReady(am_addr_t destination) {}
}
