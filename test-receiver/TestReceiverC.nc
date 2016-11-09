#include "TestReceiver.h"

#define SENDER1 93
#define SENDER2 67
#define RECEIVER 100

#define SEND_PERIOD 2000
#define SEND_DELAY 1000
#define NUM_MSGS 100
#define REQUIRE_ACK 0

module TestReceiverC {
  uses {
    interface Boot;
    interface SplitControl as SerialControl;
    interface SplitControl as RadiosControl;
    interface Random;
    interface SerialLogger;
    interface AMSend as Radio1Send;
    interface AMSend as Radio2Send;
    interface Receive as Radio1Receive;
    interface Receive as Radio2Receive;
    interface Timer<TMilli> as SendTimer;
    interface Timer<TMilli> as FinishTimer;
    interface PacketAcknowledgements as Radio1Ack;
    interface PacketAcknowledgements as Radio2Ack;
  }
}

implementation {

  uint16_t statSerialStartAttempts = 0;
  uint16_t statRadioStartAttempts = 0;

  uint16_t radio1Received = 0;
  uint16_t radio2Received = 0;
  uint16_t radio1Total = 0;
  uint16_t radio2Total = 0;

  message_t msgBuffer;

  event void Boot.booted() {
    call SerialControl.start();
  }

  event void SerialControl.startDone(error_t err) {
    if (err != SUCCESS) {
      statSerialStartAttempts++;
      call SerialControl.start();
    } else {
      call RadiosControl.start();
    }
  }

  event void SerialControl.stopDone(error_t err) {}

  event void RadiosControl.startDone(error_t err) {
    if (err != SUCCESS) {
      statRadioStartAttempts++;
      call RadiosControl.start();
    } else {
      call SerialLogger.log(LOG_SERIAL_START_ATTEMPTS, statSerialStartAttempts);
      call SerialLogger.log(LOG_RADIO_START_ATTEMPTS, statRadioStartAttempts);
      if (TOS_NODE_ID == SENDER1) {
        call SendTimer.startPeriodic(SEND_PERIOD);
        call FinishTimer.startOneShot(SEND_PERIOD * (NUM_MSGS+1));
      } else if (TOS_NODE_ID == SENDER2) {
        call SendTimer.startPeriodicAt(SEND_DELAY, SEND_PERIOD);
        call FinishTimer.startOneShot(SEND_PERIOD * (NUM_MSGS+1));
      } else if (TOS_NODE_ID == RECEIVER) {
        call FinishTimer.startOneShot(SEND_PERIOD * (NUM_MSGS+1));
      }
    }
  }

  event void RadiosControl.stopDone(error_t err) {}

  event void SendTimer.fired() {
    receiver_msg_t* msg;
    error_t eval;
    if (TOS_NODE_ID == SENDER1) {
      msg = call Radio1Send.getPayload(&msgBuffer, sizeof(receiver_msg_t));
      msg->source = TOS_NODE_ID;
      msg->destination = RECEIVER;
      msg->seqno = radio1Total;
      if (REQUIRE_ACK) {
        call Radio1Ack.requestAck(&msgBuffer);
      }
      eval = call Radio1Send.send(RECEIVER, &msgBuffer, sizeof(receiver_msg_t));
      if (eval == SUCCESS) {
        call SerialLogger.log(LOG_RADIO_1_SEND, radio1Total);
        radio1Total++;
      } else {
        call SerialLogger.log(LOG_RADIO_1_SEND_ERROR, eval);
      }
    } else if (TOS_NODE_ID == SENDER2) {
      msg = call Radio2Send.getPayload(&msgBuffer, sizeof(receiver_msg_t));
      msg->source = TOS_NODE_ID;
      msg->destination = RECEIVER;
      msg->seqno = radio2Total;
      if (REQUIRE_ACK) {
        call Radio2Ack.requestAck(&msgBuffer);
      }
      eval = call Radio2Send.send(RECEIVER, &msgBuffer, sizeof(receiver_msg_t));
      if (eval == SUCCESS) {
        call SerialLogger.log(LOG_RADIO_2_SEND, radio2Total);
        radio2Total++;
      } else {
        call SerialLogger.log(LOG_RADIO_2_SEND_ERROR, eval);
      }
    }
  }

  event void Radio1Send.sendDone(message_t* msg, error_t error) {
    if (error == SUCCESS) {
      call SerialLogger.log(LOG_RADIO_1_SEND_DONE, error);
    } else {
      call SerialLogger.log(LOG_RADIO_1_SEND_DONE_ERROR, error);
    }
  }

  event void Radio2Send.sendDone(message_t* msg, error_t error) {
    if (error == SUCCESS) {
      call SerialLogger.log(LOG_RADIO_2_SEND_DONE, error);
    } else {
      call SerialLogger.log(LOG_RADIO_2_SEND_DONE_ERROR, error);
    }
  }

  event message_t* Radio1Receive.receive(message_t* msg, void* payload,
                                         uint8_t len) {
    receiver_msg_t* rmsg = (receiver_msg_t*) payload;
    call SerialLogger.log(LOG_RADIO_1_RECEIVED, rmsg->seqno);
    radio1Received++;
    return msg;
  }

  event message_t* Radio2Receive.receive(message_t* msg, void* payload,
                                         uint8_t len) {
    receiver_msg_t* rmsg = (receiver_msg_t*) payload;
    call SerialLogger.log(LOG_RADIO_2_RECEIVED, rmsg->seqno);
    radio2Received++;
    return msg;
  }

  event void FinishTimer.fired() {
    if (TOS_NODE_ID == SENDER1) {
      call SerialLogger.log(LOG_RADIO_1_TOTAL, radio1Total);
    } else if (TOS_NODE_ID == SENDER2) {
      call SerialLogger.log(LOG_RADIO_2_TOTAL, radio2Total);
    } else if (TOS_NODE_ID == RECEIVER) {
      call SerialLogger.log(LOG_RADIO_1_RECEIVED_TOTAL, radio1Received);
      call SerialLogger.log(LOG_RADIO_2_RECEIVED_TOTAL, radio2Received);
    }
  }

}
