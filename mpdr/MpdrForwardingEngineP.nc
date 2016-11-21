#include "Mpdr.h"

generic module MpdrForwardingEngineP() {
  provides {
    interface StdControl;
    interface AMSend;
    interface Receive;
    interface Packet;
    interface MpdrStats;
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
    interface LocalTime<TMilli>;
  }
}

implementation {

  bool radio1Busy = FALSE;
  bool radio2Busy = FALSE;
  uint8_t radio = 1;
  bool requireAck = FALSE;

  // Stats
  uint16_t statSentRadio1 = 0;
  uint16_t statSentRadio2 = 0;
  uint16_t statReceivedRadio1 = 0;
  uint16_t statReceivedRadio2 = 0;
  uint16_t statDropped = 0;
  uint32_t statStartTime1 = 0;
  uint32_t statStartTime2 = 0;
  uint32_t statEndTime1 = 0;
  uint32_t statEndTime2 = 0;

  error_t sendRadio1() {
    message_t* msg;
    mpdr_msg_hdr_t* msg_hdr;
    uint8_t len;
    error_t result;
    if (radio1Busy) {
      return EBUSY;
    }
    if (call Radio1Queue.empty()) {
      return FAIL;
    }
    msg = call Radio1Queue.head();
    msg_hdr = call Radio1Send.getPayload(msg, sizeof(mpdr_msg_hdr_t));
    len = call Radio1Packet.payloadLength(msg);
    if (requireAck) {
      result = call Radio1Ack.requestAck(msg);
    }
    result = call Radio1Send.send(msg_hdr->next_hop, msg, len);
    if (result == SUCCESS) {
      call Radio1Queue.dequeue();
      radio1Busy = TRUE;
      statSentRadio1++;
    } else {
      // Drop the packet for now
      call SerialLogger.log(LOG_RADIO_1_SEND_RESULT, result);
      call Radio1Queue.dequeue();
    }
    if (statStartTime1 == 0) {
      statStartTime1 = call LocalTime.get();
    }
    statEndTime1 = call LocalTime.get();
    return result;
  }

  error_t sendRadio2() {
    message_t* msg;
    mpdr_msg_hdr_t* msg_hdr;
    uint8_t len;
    error_t result;
    if (radio2Busy) {
      return EBUSY;
    }
    if (call Radio2Queue.empty()) {
      return FAIL;
    }
    msg = call Radio2Queue.head();
    msg_hdr = call Radio2Send.getPayload(msg, sizeof(mpdr_msg_hdr_t));
    len = call Radio2Packet.payloadLength(msg);
    if (requireAck) {
      result = call Radio2Ack.requestAck(msg);
    }
    result = call Radio2Send.send(msg_hdr->next_hop, msg, len);
    if (result == SUCCESS) {
      call Radio2Queue.dequeue();
      radio2Busy = TRUE;
      statSentRadio2++;
    } else {
      // Drop the packet for now
      call SerialLogger.log(LOG_RADIO_2_SEND_RESULT, result);
      call Radio2Queue.dequeue();
    }
    if (statStartTime2 == 0) {
      statStartTime2 = call LocalTime.get();
    }
    statEndTime2 = call LocalTime.get();
    return result;
  }

  command error_t StdControl.start() {
    dbg("StdControl", "MpdrForwardingEngineP started\n");
    return SUCCESS;
  }

  command error_t StdControl.stop() {
    dbg("StdControl", "MpdrForwardingEngineP stopped\n");
    return SUCCESS;
  }

  command error_t AMSend.send(am_addr_t addr, message_t* msg, uint8_t len) {
    mpdr_msg_hdr_t* msg_hdr;
    am_addr_t next1 = 0, next2 = 0;
    error_t result = call Routing.getSendAddresses(addr, &next1, &next2);
    if (result == FAIL) {
      return FAIL;
    }
    if (radio == 1) {
      msg_hdr = call Radio1Send.getPayload(msg, sizeof(mpdr_msg_hdr_t));
      msg_hdr->source = TOS_NODE_ID;
      msg_hdr->destination = addr;
      msg_hdr->next_hop = next1;
      result = call Radio1Queue.enqueue(msg);
      if (result == SUCCESS) {
        result = sendRadio1();
      } else {
        call SerialLogger.log(LOG_QUEUE_1_ERROR, result);
      }
      if (call Routing.getNumPaths() == 2) {
        radio = 2;
      }
    } else {
      msg_hdr = call Radio2Send.getPayload(msg, sizeof(mpdr_msg_hdr_t));
      msg_hdr->source = TOS_NODE_ID;
      msg_hdr->destination = addr;
      msg_hdr->next_hop = next2;
      result = call Radio2Queue.enqueue(msg);
      if (result == SUCCESS) {
        result = sendRadio2();
      } else {
        call SerialLogger.log(LOG_QUEUE_2_ERROR, result);
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
    mpdr_msg_hdr_t* msg_hdr = (mpdr_msg_hdr_t*) payload;
    message_t* send_msg;
    mpdr_msg_hdr_t* send_msg_hdr;
    am_addr_t next_hop;
    error_t result;

    /*uint16_t* seqno = (uint16_t*) (payload + sizeof(mpdr_msg_hdr_t) + 1);
    call SerialLogger.log(LOG_RECEIVED_RADIO_1_SEQNO, *seqno);*/

    statReceivedRadio1++;

    if (statStartTime1 == 0) {
      statStartTime1 = call LocalTime.get();
    }
    statEndTime1 = call LocalTime.get();

    if (msg_hdr->destination != TOS_NODE_ID) {
      /*
        Forward message
      */
      send_msg = call MessagePool.get();
      if (send_msg == NULL) {
        statDropped++;
        call SerialLogger.log(LOG_DROP_COUNT, statDropped);
        return msg;
      }
      memcpy(send_msg, msg, sizeof(message_t));
      send_msg_hdr = call Radio2Send.getPayload(send_msg,
                                                sizeof(mpdr_msg_hdr_t));
      next_hop = call Routing.getNextHop(msg_hdr->destination);
      // send_msg_hdr->source = msg_hdr->source;
      // send_msg_hdr->destination = msg_hdr->destination;
      send_msg_hdr->next_hop = next_hop;
      result = call Radio2Queue.enqueue(send_msg);
      if (result == SUCCESS) {
        sendRadio2();
      } else {
        call SerialLogger.log(LOG_QUEUE_2_ERROR, result);
      }
    } else {
      /*
        Receive message
      */
      payload += sizeof(mpdr_msg_hdr_t);
      len -= sizeof(mpdr_msg_hdr_t);
      signal Receive.receive(msg, payload, len);
    }
    return msg;
  }

  event message_t* Radio2Receive.receive(message_t* msg, void* payload,
                                         uint8_t len) {
    mpdr_msg_hdr_t* msg_hdr = (mpdr_msg_hdr_t*) payload;
    message_t* send_msg;
    mpdr_msg_hdr_t* send_msg_hdr;
    am_addr_t next_hop;
    error_t result;

    /*uint16_t* seqno = (uint16_t*) (payload + sizeof(mpdr_msg_hdr_t) + 1);
    call SerialLogger.log(LOG_RECEIVED_RADIO_2_SEQNO, *seqno);*/

    statReceivedRadio2++;

    if (statStartTime2 == 0) {
      statStartTime2 = call LocalTime.get();
    }
    statEndTime2 = call LocalTime.get();

    if (msg_hdr->destination != TOS_NODE_ID) {
      /*
        Forward message
      */
      send_msg = call MessagePool.get();
      if (send_msg == NULL) {
        statDropped++;
        call SerialLogger.log(LOG_DROP_COUNT, statDropped);
        return msg;
      }
      memcpy(send_msg, msg, sizeof(message_t));
      send_msg_hdr = call Radio1Send.getPayload(send_msg,
                                                sizeof(mpdr_msg_hdr_t));
      next_hop = call Routing.getNextHop(msg_hdr->destination);
      // send_msg_hdr->source = msg_hdr->source;
      // send_msg_hdr->destination = msg_hdr->destination;
      send_msg_hdr->next_hop = next_hop;
      result = call Radio1Queue.enqueue(send_msg);
      if (result == SUCCESS) {
        sendRadio1();
      } else {
        call SerialLogger.log(LOG_QUEUE_1_ERROR, result);
      }
    } else {
      /*
        Receive message
      */
      payload += sizeof(mpdr_msg_hdr_t);
      len -= sizeof(mpdr_msg_hdr_t);
      signal Receive.receive(msg, payload, len);
    }
    return msg;
  }

  event void Radio1Send.sendDone(message_t* msg, error_t error) {
    mpdr_msg_hdr_t* msg_hdr;
    msg_hdr = call Radio1Send.getPayload(msg, sizeof(mpdr_msg_hdr_t));
    if (error != SUCCESS) {
      call SerialLogger.log(LOG_SEND_DONE_1_ERROR, error);
    }
    if (msg_hdr->source == TOS_NODE_ID) {
      signal AMSend.sendDone(msg, error);
    } else {
      call MessagePool.put(msg);
    }
    radio1Busy = FALSE;
    if (!call Radio1Queue.empty()) {
      sendRadio1();
    }
  }

  event void Radio2Send.sendDone(message_t* msg, error_t error) {
    mpdr_msg_hdr_t* msg_hdr;
    msg_hdr = call Radio2Send.getPayload(msg, sizeof(mpdr_msg_hdr_t));
    if (error != SUCCESS) {
      call SerialLogger.log(LOG_SEND_DONE_2_ERROR, error);
    }
    if (msg_hdr->source == TOS_NODE_ID) {
      signal AMSend.sendDone(msg, error);
    } else {
      call MessagePool.put(msg);
    }
    radio2Busy = FALSE;
    if (!call Radio2Queue.empty()) {
      sendRadio2();
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

  /*
    Stats Commands
  */

  command uint16_t MpdrStats.getSentRadio1() {
    return statSentRadio1;
  }

  command uint16_t MpdrStats.getSentRadio2() {
    return statSentRadio2;
  }

  command uint16_t MpdrStats.getReceivedRadio1() {
    return statReceivedRadio1;
  }

  command uint16_t MpdrStats.getReceivedRadio2() {
    return statReceivedRadio2;
  }

  command uint16_t MpdrStats.getDropped() {
    return statDropped;
  }

  command uint32_t MpdrStats.getTimeRadio1() {
    return statEndTime1 - statStartTime1;
  }

  command uint32_t MpdrStats.getTimeRadio2() {
    return statEndTime2 - statStartTime2;
  }

  command void MpdrStats.clear() {
    statSentRadio1 = 0;
    statSentRadio2 = 0;
    statReceivedRadio1 = 0;
    statReceivedRadio2 = 0;
    statDropped = 0;
    statStartTime1 = 0;
    statStartTime2 = 0;
  }

}

// Fix
