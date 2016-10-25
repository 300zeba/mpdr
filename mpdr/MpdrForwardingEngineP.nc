#include "Mpdr.h"
#include "../serial-logger/SerialLogger.h"

generic module MpdrForwardingEngineP() {
  provides {
    interface StdControl;
    interface AMSend;
    interface Receive;
    interface Packet;
  }
  uses {
    interface AMSend as Radio1Send;
    interface AMSend as Radio2Send;
    interface Receive as Radio1Receive;
    interface Receive as Radio2Receive;
    interface Packet as Radio1Packet;
    interface Packet as Radio2Packet;
    interface PacketAcknowledgements as Radio1Ack;
    interface PacketAcknowledgements as Radio2Ack;

    interface MpdrRouting as Routing;
    interface Pool<message_t> as MessagePool;
    interface Queue<message_t*> as Radio1Queue;
    interface Queue<message_t*> as Radio2Queue;
    interface SerialLogger;
  }
}

implementation {

  bool radio1Busy = FALSE;
  bool radio2Busy = FALSE;
  bool signalSendDone1 = FALSE;
  bool signalSendDone2 = FALSE;
  uint8_t radio = 2;
  uint16_t dropCount = 0;

  command error_t StdControl.start() {
    dbg("StdControl", "MpdrForwardingEngineP started\n");
    return SUCCESS;
  }

  command error_t StdControl.stop() {
    dbg("StdControl", "MpdrForwardingEngineP stopped\n");
    return SUCCESS;
  }

  command error_t AMSend.send(am_addr_t addr, message_t* msg, uint8_t len) {
    message_t* msgBuffer = msg;
    mpdr_msg_hdr_t* msg_hdr;
    am_addr_t next1 = 0, next2 = 0;
    error_t result = call Routing.getSendAddresses(addr, &next1, &next2);
    if (msgBuffer == NULL) {
      dropCount++;
      return FAIL;
    }
    if (result == FAIL) {
      return FAIL;
    }
    if (radio == 1) {
      msg_hdr = call Radio1Send.getPayload(msgBuffer, sizeof(mpdr_msg_hdr_t));
      msg_hdr->source = TOS_NODE_ID;
      msg_hdr->destination = addr;
      msg_hdr->next_hop = next1;
      if (!radio1Busy) {
        call SerialLogger.log(LOG_SENDING_RADIO_1_TO, next1);
        result = call Radio1Ack.requestAck(msgBuffer);
        if (result == SUCCESS) {
          result = call Radio1Send.send(next1, msgBuffer,
                                        len + sizeof(mpdr_msg_hdr_t));
          call SerialLogger.log(LOG_RADIO_1_SEND_RESULT, result);
          if (result == SUCCESS) {
            radio1Busy = TRUE;
            signalSendDone1 = TRUE;
          }
        } else {
          call SerialLogger.log(LOG_REQUEST_ACK_1_ERROR, result);
        }
      } else {
        result = call Radio1Queue.enqueue(msgBuffer);
        call SerialLogger.log(LOG_ENQUEUEING_RADIO_1, result);
      }
      if (call Routing.getNumPaths() == 2) {
        radio = 2;
      }
    } else {
      msg_hdr = call Radio2Send.getPayload(msgBuffer, sizeof(mpdr_msg_hdr_t));
      msg_hdr->source = TOS_NODE_ID;
      msg_hdr->destination = addr;
      msg_hdr->next_hop = next2;
      if (!radio2Busy) {
        call SerialLogger.log(LOG_SENDING_RADIO_2_TO, next2);
        result = call Radio2Ack.requestAck(msgBuffer);
        if (result == SUCCESS) {
          result = call Radio2Send.send(next2, msgBuffer,
                                        len + sizeof(mpdr_msg_hdr_t));
          call SerialLogger.log(LOG_RADIO_2_SEND_RESULT, result);
          if (result == SUCCESS) {
            radio2Busy = TRUE;
            signalSendDone2 = TRUE;
          }
        } else {
          call SerialLogger.log(LOG_REQUEST_ACK_2_ERROR, result);
        }
      } else {
        result = call Radio2Queue.enqueue(msgBuffer);
        call SerialLogger.log(LOG_ENQUEUEING_RADIO_2, result);
      }
      if (call Routing.getNumPaths() == 2) {
        radio = 1;
      }
    }
    return result;
  }

  command error_t AMSend.cancel(message_t* msg) {
    // TODO: implement the cancel
    return FAIL;
  }

  command uint8_t AMSend.maxPayloadLength() {
    return call Packet.maxPayloadLength();
  }

  command void* AMSend.getPayload(message_t* msg, uint8_t len) {
    return call Packet.getPayload(msg, len);
  }


  event message_t* Radio1Receive.receive(message_t* msg, void* payload,
                                         uint8_t len) {
    mpdr_msg_hdr_t* rmsg = (mpdr_msg_hdr_t*) payload;
    message_t* msgBuffer;
    mpdr_msg_hdr_t* smsg;
    am_addr_t next_hop;
    error_t result;
    // uint16_t* seqno = (uint16_t*) (payload + sizeof(mpdr_msg_hdr_t));

    call SerialLogger.log(LOG_RECEIVED_RADIO_1_SOURCE, rmsg->source);
    call SerialLogger.log(LOG_RECEIVED_RADIO_1_DESTINATION, rmsg->destination);
    // call SerialLogger.log(LOG_RECEIVED_RADIO_1_NEXT_HOP, rmsg->next_hop);

    if (rmsg->destination != TOS_NODE_ID) {
      call SerialLogger.log(LOG_TOS_NODE_ID, TOS_NODE_ID);
      msgBuffer = call MessagePool.get();
      if (msgBuffer == NULL) {
        dropCount++;
        call SerialLogger.log(LOG_DROP_COUNT, dropCount);
        return msg;
      }
      memcpy(msgBuffer, msg, sizeof(message_t));
      smsg = call Radio2Send.getPayload(msgBuffer, sizeof(mpdr_msg_hdr_t));
      next_hop = call Routing.getNextHop(rmsg->destination);
      call SerialLogger.log(LOG_GET_NEXT_HOP, next_hop);
      smsg->source = rmsg->source;
      smsg->destination = rmsg->destination;
      smsg->next_hop = next_hop;
      if (!radio2Busy) {
        result = call Radio2Ack.requestAck(msgBuffer);
        if (result == SUCCESS) {
          result = call Radio2Send.send(next_hop, msgBuffer, len);
          call SerialLogger.log(LOG_RADIO_2_SEND_RESULT, result);
          if (result == SUCCESS) {
            radio2Busy = TRUE;
          }
        } else {
          call SerialLogger.log(LOG_REQUEST_ACK_2_ERROR, result);
        }
      } else {
        call Packet.setPayloadLength(msgBuffer, len);
        result = call Radio2Queue.enqueue(msgBuffer);
        call SerialLogger.log(LOG_RADIO_2_ENQUEUE_RESULT, result);
      }
    } else {
      payload += sizeof(mpdr_msg_hdr_t);
      len -= sizeof(mpdr_msg_hdr_t);
      signal Receive.receive(msg, payload, len);
    }
    return msg;
  }

  event message_t* Radio2Receive.receive(message_t* msg, void* payload,
                                         uint8_t len) {
    mpdr_msg_hdr_t* rmsg = (mpdr_msg_hdr_t*) payload;
    message_t* msgBuffer;
    mpdr_msg_hdr_t* smsg;
    am_addr_t next_hop;
    error_t result;
    // uint16_t* seqno = (uint16_t*) (payload + sizeof(mpdr_msg_hdr_t));

    call SerialLogger.log(LOG_RECEIVED_RADIO_2_SOURCE, rmsg->source);
    call SerialLogger.log(LOG_RECEIVED_RADIO_2_DESTINATION, rmsg->destination);
    // call SerialLogger.log(LOG_RECEIVED_RADIO_2_NEXT_HOP, rmsg->next_hop);

    if (rmsg->destination != TOS_NODE_ID) {
      call SerialLogger.log(LOG_TOS_NODE_ID, TOS_NODE_ID);
      msgBuffer = call MessagePool.get();
      if (msgBuffer == NULL) {
        dropCount++;
        call SerialLogger.log(LOG_DROP_COUNT, dropCount);
        return msg;
      }
      memcpy(msgBuffer, msg, sizeof(message_t));
      smsg = call Radio1Send.getPayload(msgBuffer, sizeof(mpdr_msg_hdr_t));
      next_hop = call Routing.getNextHop(rmsg->destination);
      call SerialLogger.log(LOG_GET_NEXT_HOP, next_hop);
      smsg->source = rmsg->source;
      smsg->destination = rmsg->destination;
      smsg->next_hop = next_hop;
      if (!radio1Busy) {
        result = call Radio1Ack.requestAck(msgBuffer);
        if (result == SUCCESS) {
          result = call Radio1Send.send(next_hop, msgBuffer, len);
          call SerialLogger.log(LOG_RADIO_1_SEND_RESULT, result);
          if (result == SUCCESS) {
            radio1Busy = TRUE;
          }
        } else {
          call SerialLogger.log(LOG_REQUEST_ACK_1_ERROR, result);
        }
      } else {
        call Packet.setPayloadLength(msgBuffer, len);
        result = call Radio1Queue.enqueue(msgBuffer);
        call SerialLogger.log(LOG_RADIO_1_ENQUEUE_RESULT, result);
      }
    } else {
      payload += sizeof(mpdr_msg_hdr_t);
      len -= sizeof(mpdr_msg_hdr_t);
      signal Receive.receive(msg, payload, len);
    }
    return msg;
  }

  event void Radio1Send.sendDone(message_t* msg, error_t error) {
    mpdr_msg_hdr_t* rmsg;
    uint8_t len;
    error_t result;
    if (error != SUCCESS) {
      call SerialLogger.log(LOG_SEND_DONE_1_ERROR, error);
    }
    if (signalSendDone1) {
      signal AMSend.sendDone(msg, error);
      signalSendDone1 = FALSE;
    } else {
      call MessagePool.put(msg);
    }
    if (call Radio1Queue.empty()) {
      radio1Busy = FALSE;
    } else {
      msg = call Radio1Queue.dequeue();
      rmsg = call Radio1Send.getPayload(msg, sizeof(mpdr_msg_hdr_t));
      len = call Packet.payloadLength(msg);
      result = call Radio1Ack.requestAck(msg);
      if (result == SUCCESS) {
        result = call Radio1Send.send(rmsg->next_hop, msg,
                                      len + sizeof(mpdr_msg_hdr_t));
        call SerialLogger.log(LOG_RADIO_1_SEND_RESULT_2, result);
      } else {
        call SerialLogger.log(LOG_REQUEST_ACK_1_ERROR, result);
      }
    }
  }

  event void Radio2Send.sendDone(message_t* msg, error_t error) {
    mpdr_msg_hdr_t* rmsg;
    uint8_t len;
    error_t result;
    if (error != SUCCESS) {
      call SerialLogger.log(LOG_SEND_DONE_2_ERROR, error);
    }
    if (signalSendDone2) {
      signal AMSend.sendDone(msg, error);
      signalSendDone2 = FALSE;
    } else {
      call MessagePool.put(msg);
    }
    if (call Radio2Queue.empty()) {
      radio2Busy = FALSE;
    } else {
      msg = call Radio2Queue.dequeue();
      rmsg = call Radio2Send.getPayload(msg, sizeof(mpdr_msg_hdr_t));
      len = call Packet.payloadLength(msg);
      result = call Radio2Ack.requestAck(msg);
      if (result == SUCCESS) {
        result = call Radio2Send.send(rmsg->next_hop, msg,
                                      len + sizeof(mpdr_msg_hdr_t));
        call SerialLogger.log(LOG_RADIO_2_SEND_RESULT_2, result);
      } else {
        call SerialLogger.log(LOG_REQUEST_ACK_2_ERROR, result);
      }
    }
  }

  event void Routing.pathsReady(am_addr_t destination) {
  }

  /*
    Packet commands
  */
  command void Packet.clear(message_t* msg) {
    call Radio1Packet.clear(msg);
    call Radio2Packet.clear(msg);
  }

  command uint8_t Packet.payloadLength(message_t* msg) {
    uint8_t len1 = call Radio1Packet.payloadLength(msg);
    uint8_t len2 = call Radio2Packet.payloadLength(msg);
    if (len1 == len2) {
      return len1 - sizeof(mpdr_msg_hdr_t);
    } else {
      // call SerialLogger.log(44, len1);
      // call SerialLogger.log(45, len2);
      if (len1 < len2) {
        return len1 - sizeof(mpdr_msg_hdr_t);
      } else {
        return len2 - sizeof(mpdr_msg_hdr_t);
      }
    }
  }

  command void Packet.setPayloadLength(message_t* msg, uint8_t len) {
    call Radio1Packet.setPayloadLength(msg, len + sizeof(mpdr_msg_hdr_t));
    call Radio2Packet.setPayloadLength(msg, len + sizeof(mpdr_msg_hdr_t));
  }

  command uint8_t Packet.maxPayloadLength() {
    uint8_t max1 = call Radio1Packet.maxPayloadLength();
    uint8_t max2 = call Radio2Packet.maxPayloadLength();
    if (max1 == max2) {
      return max1 - sizeof(mpdr_msg_hdr_t);
    }
    // call SerialLogger.log(46, max1);
    // call SerialLogger.log(47, max2);
    if (max1 < max2) {
      return max1 - sizeof(mpdr_msg_hdr_t);
    }
    return max2 - sizeof(mpdr_msg_hdr_t);
  }

  command void* Packet.getPayload(message_t* msg, uint8_t len) {
    void* payload1 = call Radio1Packet.getPayload(msg, len);
    void* payload2 = call Radio2Packet.getPayload(msg, len);
    if (payload1 == payload2) {
      return payload1 + sizeof(mpdr_msg_hdr_t);
    }
    // call SerialLogger.log(48, (uint16_t) payload1);
    // call SerialLogger.log(49, (uint16_t) payload2);
    if (payload1 > payload2) {
      return payload1 + sizeof(mpdr_msg_hdr_t);
    }
    return payload2 + sizeof(mpdr_msg_hdr_t);
  }

}
