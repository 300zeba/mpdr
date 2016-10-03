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

  /*uint8_t destinationNode = 1;
  uint8_t sourceNode = 100;
  uint8_t sourceRoutes[2][3] = {
    {16, 2, 2},
    {93, 1, 1}
  };
  uint8_t relayLength = 6;
  uint8_t relayNodes[6] = {55, 65, 16, 56, 62, 93};
  uint8_t relayRoutes[6][3] = {
    {1, 1, 1},
    {55, 2, 1},
    {65, 1, 2},
    {1, 2, 2},
    {56, 1, 2},
    {62, 2, 1}
  };*/

  uint8_t destinationNode = 2;
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

  uint8_t getDestinationRadio1Channel() {
    uint8_t i;
    for (i = 0; i < relayLength; i++) {
      if (relayRoutes[i][0] == destinationNode && relayRoutes[i][1] == 1) {
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
      call InitTimer.startOneShot(10000);
    }
  }

  event void RadiosControl.stopDone(error_t error) {}

  event void InitTimer.fired() {
    uint8_t relayIndex;
    uint8_t radio;
    uint8_t channel1;
    uint8_t channel2;
    if (TOS_NODE_ID == destinationNode) {
      channel1 = getDestinationRadio1Channel();
      channel2 = (channel1 == 1)? 2: 1;
      call MpdrRouting.setRadioChannel(1, channel1);
      call MpdrRouting.setRadioChannel(2, channel2);
      // call RootTimer.startOneShot(60000);
    } else if (TOS_NODE_ID == sourceNode) {
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
      call SendTimer.startPeriodic(500);
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
