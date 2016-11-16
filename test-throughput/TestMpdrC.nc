#include "TestMpdr.h"
#include "../serial-logger/SerialLogger.h"

// Define NON_STOP to 1 to send a message after a sendDone is signaled.
// Define to 0 to send a message only each SEND_PERIOD.
#define NON_STOP 1

// Time to send each message if NON_STOP is not defined.
#define SEND_PERIOD 100

// Define TEST_DURATION to the maximum amount of time the test to run.
// Set to 0 for unlimited.
#define TEST_DURATION 30000

// Define NUM_MSGS to the maximum number of messages sent.
// Set to 0 for unlimited.
#define NUM_MSGS 0

// Time to finish the experiment.
#define FINISH_TIME 60000

module TestMpdrC {
  uses {
    interface Boot;

    interface Timer<TMilli> as InitTimer;
    interface Timer<TMilli> as SendTimer;
    interface Timer<TMilli> as StopTimer;
    interface Timer<TMilli> as FinishTimer;

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

  message_t msgBuffer;
  bool transmitting = FALSE;

  uint16_t sendCount = 0;
  uint16_t receivedCount = 0;
  uint16_t messageSize;

  uint32_t startTime = 0;
  uint32_t endTime = 0;
  uint32_t elapsedTime = 0;

  enum {
    SEND_PATH_1,
    SEND_PATH_2,
    RESEND_PATHS,
    SEND_STATISTICS,
  };

  uint8_t rootAction;
  uint8_t numPaths = 2;

  // Routes:
  uint8_t destinationNode = 10;
  uint8_t sourceNode = 1;
  uint8_t sourceRoutes[2][3] = {
    {5, 1, 1},
    {6, 2, 2},
  };
  uint8_t relayLength = 2;
  uint8_t relayNodes[2] = {5, 6, };
  uint8_t relayRoutes[2][3] = {
    {10, 2, 1},
    {10, 1, 2},
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
      call FinishTimer.startOneShot(FINISH_TIME);
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
      call FinishTimer.startOneShot(FINISH_TIME);
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
    error_t error;
    if (NUM_MSGS != 0 && sendCount > NUM_MSGS) {
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
    call MpdrPacket.setPayloadLength(msg, sizeof(mpdr_test_msg_t));
    error = call MpdrSend.send(destinationNode, msg, sizeof(mpdr_test_msg_t));
    if (error != SUCCESS) {
      call SerialLogger.log(LOG_ERROR_MPDR_SEND, error);
    }
    endTime = call FinishTimer.getNow();
  }

  event void SendTimer.fired() {
    if (call SendTimer.isOneShot()) {
      call SerialLogger.log(LOG_START_SENDING, 0);
      startTime = call FinishTimer.getNow();
      transmitting = TRUE;
      sendMessage();
      if (NON_STOP == 0) {
        call SendTimer.startPeriodic(SEND_PERIOD);
      }
      if (TEST_DURATION != 0) {
        call StopTimer.startOneShot(TEST_DURATION);
      }
    } else {
      if (transmitting) {
        sendMessage();
      } else {
        call SendTimer.stop();
      }
    }
  }

  event void StopTimer.fired() {
    transmitting = FALSE;
    call SendTimer.stop();
  }

  event void MpdrSend.sendDone(message_t* msg, error_t error) {
    // mpdr_test_msg_t* payload;
    if (error == SUCCESS) {
      sendCount++;
      // payload = (mpdr_test_msg_t*) call MpdrPacket.getPayload(msg,
      //                                                  sizeof(mpdr_test_msg_t));
      // call SerialLogger.log(LOG_MPDR_SEND_DONE, payload->seqno);
    } else {
      call SerialLogger.log(LOG_ERROR_MPDR_SEND_DONE, error);
    }
    if (NON_STOP) {
      sendMessage();
    }
  }

  event message_t* MpdrReceive.receive(message_t* msg, void* payload,
                                       uint8_t len) {
    uint8_t i;
    mpdr_test_msg_t* rcvdPayload = (mpdr_test_msg_t*) payload;
    receivedCount++;
    sendCount = rcvdPayload->seqno;
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

  event void FinishTimer.fired() {
    if (TOS_NODE_ID == sourceNode) {
      call SerialLogger.log(LOG_SEND_COUNT, sendCount);
    } else if (TOS_NODE_ID == destinationNode) {
      call SerialLogger.log(LOG_RECEIVED_COUNT, receivedCount);
    }
    elapsedTime = endTime - startTime;
    call SerialLogger.log(LOG_ELAPSED_TIME, elapsedTime);
    call SerialLogger.log(LOG_MESSAGE_SIZE, sizeof(message_t));
    call SerialLogger.log(LOG_PAYLOAD_SIZE, sizeof(mpdr_test_msg_t));
  }

  event void MpdrRouting.pathsReady(am_addr_t destination) {}
}

//Fix
