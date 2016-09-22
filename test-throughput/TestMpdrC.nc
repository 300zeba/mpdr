#include "TestMpdr.h"
#include "../serial-logger/SerialLogger.h"

#define ROOT_NODE 2
#define NUM_HOPS 3

module TestMpdrC {
  uses {
    interface Boot;

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

  uint8_t destinationNode = 2;
  uint8_t sourceNode = 79;
  uint8_t sourceRoutes[2][3] = {
    {85, 1, 2},
    {29, 2, 1}
  };
  uint8_t relayNodes[4] = {56, 85, 7, 29};
  uint8_t relayRoutes[4][3] = {
    {2, 1, 1},
    {56, 2, 1},
    {2, 2, 2},
    {7, 1, 2}
  };

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
      // call SerialLogger.log(LOG_NUM_PATHS, numPaths);
      if (TOS_NODE_ID == ROOT_NODE) {
        call RootTimer.startOneShot(5000);
        rootAction = SEND_PATH_1;
      }
    }

  }

  event void RadiosControl.stopDone(error_t error) {}

  event void RootTimer.fired() {
    call SerialLogger.log(LOG_ROOT_ACTION, rootAction);
    switch (rootAction) {
      case SEND_PATH_1:
        call MpdrRouting.sendRouteMsg(m_source, m_destination, 1, path1_len, (am_addr_t*) &path1_items);
        call RootTimer.startOneShot(5000);
        if (numPaths == 2) {
          rootAction = SEND_PATH_2;
        } else {
          rootAction = RESEND_PATHS;
        }
      break;

      case SEND_PATH_2:
        call MpdrRouting.sendRouteMsg(m_source, m_destination, 2, path2_len, (am_addr_t*) &path2_items);
        call RootTimer.startOneShot(5000);
        rootAction = RESEND_PATHS;
      break;

      case RESEND_PATHS:
        if (receivedCount == 0) {
          // call SerialLogger.log(LOG_RESEND_PATHS, 0);
          // call RootTimer.startOneShot(1000);
          //rootAction = SEND_PATH_1;
          call SerialLogger.log(LOG_ROUTING_ERROR, 0);
        } else {
          call RootTimer.startOneShot(75000);
          rootAction = SEND_STATISTICS;
        }
      break;

      case SEND_STATISTICS:
        call SerialLogger.log(LOG_RECEIVED_COUNT, receivedCount);
        call SerialLogger.log(LOG_TOTAL_COUNT, totalCount);
        call SerialLogger.log(LOG_MESSAGE_SIZE, messageSize);
        call SerialLogger.log(LOG_THROUGHPUT, throughput);
      break;

    }
  }

  event void NodeTimer.fired() {
    transmitting = FALSE;
    call SerialLogger.log(LOG_TOTAL_SENT, totalCount);
  }

  event void SendTimer.fired() {
  }

  void sendMessage() {
    message_t* msg;
    mpdr_test_msg_t* payload;
    error_t error;
    msg = &msgBuffer;
    payload = (mpdr_test_msg_t*) call MpdrPacket.getPayload(msg, sizeof(mpdr_test_msg_t));
    payload->seqno = totalCount;
    payload->data[0] = sizeof(message_t);
    call MpdrPacket.setPayloadLength(msg, sizeof(mpdr_test_msg_t));
    error = call MpdrSend.send(sendTo, msg, sizeof(mpdr_test_msg_t));
    if (error != SUCCESS) {
      call SerialLogger.log(LOG_ERROR_MPDR_SEND, error);
    }
  }

  event void MpdrSend.sendDone(message_t* msg, error_t error) {
    if (error == SUCCESS) {
      totalCount++;
      call SerialLogger.log(LOG_MPDR_SEND_DONE, totalCount);
    } else {
      call SerialLogger.log(LOG_ERROR_MPDR_SEND_DONE, error);
    }
    if (totalCount > 100) {
      transmitting = FALSE;
    }
    if (transmitting) {
      sendMessage();
    }
  }

  event message_t* MpdrReceive.receive(message_t* msg, void* payload, uint8_t len) {
    mpdr_test_msg_t* rcvdPayload = (mpdr_test_msg_t*) payload;
    if (!call SendTimer.isRunning()) {
      call SendTimer.startPeriodic(60000);
    }
    receivedCount++;
    totalCount = rcvdPayload->seqno;
    messageSize = rcvdPayload->data[0];
    timeElapsed = call SendTimer.getNow();
    throughput = (receivedCount * messageSize) / timeElapsed;
    call SerialLogger.log(LOG_MPDR_RECEIVE, rcvdPayload->seqno);
    return msg;
  }

  event void MpdrRouting.pathsReady(am_addr_t destination) {
    call SerialLogger.log(LOG_MPDR_PATHS_READY, destination);
    sendTo = destination;
    transmitting = TRUE;
    sendMessage();
    call NodeTimer.startOneShot(60000);
  }
}
