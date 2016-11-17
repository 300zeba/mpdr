#include "TestSender.h"

#define SENDER 1
#define RECEIVER1 5
#define RECEIVER2 6

#define NUM_RADIOS 2
#define NON_STOP_SEND 1
#define SEND_PERIOD 250
#define NUM_MSGS 1000
#define END_TIME 0
#define FINISH_TIME 60000
#define REQUIRE_ACK 0

module TestSenderC {
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
    interface Timer<TMilli> as InitTimer;
    interface Timer<TMilli> as SendTimer;
    interface Timer<TMilli> as EndTimer;
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
  bool radio1Busy = FALSE;
  bool radio2Busy = FALSE;
  uint32_t initialTime = 0;
  uint32_t endTime = 0;
  bool sending = FALSE;
  bool countingTime = FALSE;
  uint8_t radio = 1;

  message_t msgBuffer1;
  message_t msgBuffer2;
  message_t ctrlMsgBuffer;

  void sendMessage() {
    test_msg_t* msg;
    error_t eval;
    if (NUM_MSGS > 0 && (radio1Total + radio2Total) > NUM_MSGS) {
      sending = FALSE;
    }
    if (!sending) {
      return;
    }
    if (countingTime == FALSE) {
      countingTime = TRUE;
      initialTime = call FinishTimer.getNow();
    } else {
      endTime = call FinishTimer.getNow();
    }
    if (!radio1Busy) {
      radio = 1;
    } else if (!radio2Busy && NUM_RADIOS == 2) {
      radio = 2;
    } else {
      call SerialLogger.log(LOG_RADIOS_BUSY_ERROR, 0);
    }
    if (radio == 1) {
      msg = call Radio1Send.getPayload(&msgBuffer1, sizeof(test_msg_t));
      msg->source = TOS_NODE_ID;
      msg->destination = RECEIVER1;
      msg->seqno = radio1Total;
      if (REQUIRE_ACK) {
        call Radio1Ack.requestAck(&msgBuffer1);
      }
      eval = call Radio1Send.send(RECEIVER1, &msgBuffer1, sizeof(test_msg_t));
      if (eval == SUCCESS) {
        // call SerialLogger.log(LOG_RADIO_1_SEND, radio1Total);
        radio1Busy = TRUE;
        radio1Total++;
      } else {
        call SerialLogger.log(LOG_RADIO_1_SEND_ERROR, eval);
      }
    } else {
      msg = call Radio2Send.getPayload(&msgBuffer2, sizeof(test_msg_t));
      msg->source = TOS_NODE_ID;
      msg->destination = RECEIVER2;
      msg->seqno = radio2Total;
      if (REQUIRE_ACK) {
        call Radio2Ack.requestAck(&msgBuffer2);
      }
      eval = call Radio2Send.send(RECEIVER2, &msgBuffer2, sizeof(test_msg_t));
      if (eval == SUCCESS) {
        // call SerialLogger.log(LOG_RADIO_2_SEND, radio2Total);
        radio2Busy = TRUE;
        radio2Total++;
      } else {
        call SerialLogger.log(LOG_RADIO_2_SEND_ERROR, eval);
      }
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
    if (TOS_NODE_ID == SENDER) {
      sending = TRUE;
      sendMessage();
      if (NUM_RADIOS == 2) {
        sendMessage();
      }
      if (NON_STOP_SEND == 0) {
        call SendTimer.startPeriodic(SEND_PERIOD);
      }
      if (END_TIME > 0) {
        call EndTimer.startOneShot(END_TIME);
      }
    }
    call FinishTimer.startOneShot(FINISH_TIME);
  }

  event void SendTimer.fired() {
    if (sending) {
      sendMessage();
      if (NUM_RADIOS == 2) {
        sendMessage();
      }
    } else {
      call SendTimer.stop();
    }
  }

  event void EndTimer.fired() {
    sending = FALSE;
  }

  event void Radio1Send.sendDone(message_t* msg, error_t error) {
    radio1Busy = FALSE;
    if (error == SUCCESS) {
      // call SerialLogger.log(LOG_RADIO_1_SEND_DONE, error);
    } else {
      call SerialLogger.log(LOG_RADIO_1_SEND_DONE_ERROR, error);
    }
    if (NON_STOP_SEND) {
      sendMessage();
    }
  }

  event void Radio2Send.sendDone(message_t* msg, error_t error) {
    radio2Busy = FALSE;
    if (error == SUCCESS) {
      // call SerialLogger.log(LOG_RADIO_2_SEND_DONE, error);
    } else {
      call SerialLogger.log(LOG_RADIO_2_SEND_DONE_ERROR, error);
    }
    if (NON_STOP_SEND) {
      sendMessage();
    }
  }

  event message_t* Radio1Receive.receive(message_t* msg, void* payload,
                                         uint8_t len) {
    // test_msg_t* rmsg = (test_msg_t*) payload;
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
    // test_msg_t* rmsg = (test_msg_t*) payload;
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

  event void FinishTimer.fired() {
    if (TOS_NODE_ID == SENDER) {
      call SerialLogger.log(LOG_RADIO_1_TOTAL, radio1Total);
      call SerialLogger.log(LOG_RADIO_2_TOTAL, radio2Total);
    } else if (TOS_NODE_ID == RECEIVER1) {
      call SerialLogger.log(LOG_RADIO_1_RECEIVED_TOTAL, radio1Received);
    } else if (TOS_NODE_ID == RECEIVER2) {
      call SerialLogger.log(LOG_RADIO_2_RECEIVED_TOTAL, radio2Received);
    }
    call SerialLogger.log(LOG_ELAPSED_TIME, endTime - initialTime);
    call SerialLogger.log(LOG_MESSAGE_SIZE, sizeof(message_t));
    call SerialLogger.log(LOG_PAYLOAD_SIZE, sizeof(test_msg_t));
  }
}
