#include "TestReceiver.h"

#define SENDER1 13
#define SENDER2 12
#define RECEIVER 20

#define SEND_PERIOD 250
#define SEND_DELAY 0
#define NUM_MSGS 1000
#define REQUIRE_ACK 0
#define FINISH_TIME 60000
#define NON_STOP_SEND 1

module TestReceiverC {
  uses {
    interface Boot;
    interface SplitControl as SerialControl;
    interface SplitControl as RadiosControl;
    interface Random;
    interface SerialLogger;
    interface AMSend as Radio1Send;
    interface AMSend as Radio2Send;
    interface AMSend as ControlSend;
    interface Receive as Radio1Receive;
    interface Receive as Radio2Receive;
    interface Receive as ControlReceive;
    interface Timer<TMilli> as InitTimer;
    interface Timer<TMilli> as SendTimer;
    interface Timer<TMilli> as FinishTimer;
    interface PacketAcknowledgements as Radio1Ack;
    interface PacketAcknowledgements as Radio2Ack;
  }
}

implementation {

  uint16_t radio1Received = 0;
  uint16_t radio2Received = 0;
  uint16_t radio1Total = 0;
  uint16_t radio2Total = 0;
  uint32_t initialTime = 0;
  uint32_t endTime = 0;
  bool sending = FALSE;
  bool countingTime = FALSE;

  message_t msgBuffer;
  message_t ctrlMsgBuffer;

  void sendMessage() {
    receiver_msg_t* msg;
    error_t eval;
    if (countingTime == FALSE) {
      countingTime = TRUE;
      initialTime = call FinishTimer.getNow();
    } else {
      endTime = call FinishTimer.getNow();
    }
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
        // call SerialLogger.log(LOG_RADIO_1_SEND, radio1Total);
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
        // call SerialLogger.log(LOG_RADIO_2_SEND, radio2Total);
        radio2Total++;
      } else {
        call SerialLogger.log(LOG_RADIO_2_SEND_ERROR, eval);
      }
    }
  }

  void sendControl() {
    receiver_msg_t* msg = call ControlSend.getPayload(&ctrlMsgBuffer,
                                                      sizeof(receiver_msg_t));
    error_t eval;
    msg->source = TOS_NODE_ID;
    msg->destination = SENDER2;
    msg->seqno = 1;
    call Radio1Ack.requestAck(&ctrlMsgBuffer);
    eval = call ControlSend.send(SENDER2, &ctrlMsgBuffer,
                                 sizeof(receiver_msg_t));
    if (eval == SUCCESS) {
      call SerialLogger.log(LOG_CONTROL_SEND, eval);
    } else {
      call SerialLogger.log(LOG_CONTROL_SEND_ERROR, eval);
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

  event void RadiosControl.startDone(error_t err) {
    if (err != SUCCESS) {
      call RadiosControl.start();
    } else {
      call InitTimer.startOneShot(1000);
    }
  }

  event void RadiosControl.stopDone(error_t err) {}

  event void InitTimer.fired() {
    if (TOS_NODE_ID == SENDER1) {
      sendControl();
      call SendTimer.startPeriodic(SEND_PERIOD);
    }
    call FinishTimer.startOneShot(FINISH_TIME);
  }

  event void SendTimer.fired() {
    sendMessage();
    sending = TRUE;
    if (NON_STOP_SEND) {
      call SendTimer.stop();
    }
  }

  event void Radio1Send.sendDone(message_t* msg, error_t error) {
    if (error == SUCCESS) {
      // call SerialLogger.log(LOG_RADIO_1_SEND_DONE, error);
    } else {
      call SerialLogger.log(LOG_RADIO_1_SEND_DONE_ERROR, error);
    }
    if (NON_STOP_SEND && sending) {
      sendMessage();
    }
    if (NUM_MSGS != 0 && radio1Total >= NUM_MSGS) {
      call SendTimer.stop();
      sending = FALSE;
    }
  }

  event void Radio2Send.sendDone(message_t* msg, error_t error) {
    if (error == SUCCESS) {
      // call SerialLogger.log(LOG_RADIO_2_SEND_DONE, error);
    } else {
      call SerialLogger.log(LOG_RADIO_2_SEND_DONE_ERROR, error);
    }
    if (NON_STOP_SEND && sending) {
      sendMessage();
    }
    if (NUM_MSGS != 0 && radio2Total >= NUM_MSGS) {
      call SendTimer.stop();
      sending = FALSE;
    }
  }

  event void ControlSend.sendDone(message_t* msg, error_t error) {
    if (error == SUCCESS) {
      call SerialLogger.log(LOG_CONTROL_SEND_DONE, error);
    } else {
      call SerialLogger.log(LOG_CONTROL_SEND_DONE_ERROR, error);
    }
  }

  event message_t* Radio1Receive.receive(message_t* msg, void* payload,
                                         uint8_t len) {
    receiver_msg_t* rmsg = (receiver_msg_t*) payload;
    // call SerialLogger.log(LOG_RADIO_1_RECEIVED, rmsg->seqno);
    radio1Received++;
    if (countingTime == FALSE) {
      countingTime = TRUE;
      initialTime = call FinishTimer.getNow();
    } else {
      endTime = call FinishTimer.getNow();
    }
    return msg;
  }

  event message_t* Radio2Receive.receive(message_t* msg, void* payload,
                                         uint8_t len) {
    receiver_msg_t* rmsg = (receiver_msg_t*) payload;
    // call SerialLogger.log(LOG_RADIO_2_RECEIVED, rmsg->seqno);
    radio2Received++;
    if (countingTime == FALSE) {
      countingTime = TRUE;
      initialTime = call FinishTimer.getNow();
    } else {
      endTime = call FinishTimer.getNow();
    }
    return msg;
  }

  event message_t* ControlReceive.receive(message_t* msg, void* payload,
                                          uint8_t len) {
    receiver_msg_t* rmsg = (receiver_msg_t*) payload;
    call SerialLogger.log(LOG_CONTROL_RECEIVE, rmsg->source);
    if (TOS_NODE_ID == SENDER1) {
      call SendTimer.startPeriodic(SEND_PERIOD);
    } else if (TOS_NODE_ID == SENDER2) {
      call SendTimer.startPeriodic(SEND_PERIOD);
    }
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
    call SerialLogger.log(LOG_ELAPSED_TIME, endTime - initialTime);
  }

  // Fix

}
