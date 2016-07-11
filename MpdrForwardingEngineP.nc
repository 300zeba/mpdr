#include "Mpdr.h"

generic module MpdrForwardingEngineP() {
  provides {
    interface StdControl;
    interface MpdrCommunication;
  }
  uses {
    interface AMSend as Radio1Send;
    interface AMSend as Radio2Send;
    interface Receive as Radio1Receive;
    interface Receive as Radio2Receive;

    interface MpdrRouting as RoutingTable;
    interface Pool<message_t> as MessagePool;
    interface Queue<message_t*> as Radio1Queue;
    interface Queue<message_t*> as Radio2Queue;
    interface SerialLogger;
  }
}

implementation {

  bool radio1Busy = FALSE;
  bool radio2Busy = FALSE;

  uint8_t radio = 1;
  uint8_t numRoutes = 2;

  uint16_t dropCount = 0;

  command error_t StdControl.start() {
    dbg("StdControl", "MpdrForwardingEngineP started\n");
    return SUCCESS;
  }

  command error_t StdControl.stop() {
    dbg("StdControl", "MpdrForwardingEngineP stopped\n");
    return SUCCESS;
  }

  command void MpdrCommunication.setNumPaths(uint8_t num_paths) {
    numRoutes = num_paths;
    call RoutingTable.setNumRoutes(num_paths);
  }

  command error_t MpdrCommunication.send(uint16_t data, am_addr_t destination) {
    message_t* msgBuffer = call MessagePool.get();
    mpdr_msg_t* msg;
    am_addr_t next1 = 0, next2 = 0;
    error_t result = call RoutingTable.getSendAddresses(destination, &next1, &next2);
    if (msgBuffer == NULL) {
      dropCount++;
      call SerialLogger.log(81, dropCount);
      return FAIL;
    }
    if (result == FAIL) {
      return FAIL;
    }
    if (radio == 1) {
      msg = call Radio1Send.getPayload(msgBuffer, sizeof(mpdr_msg_t));
      msg->source = TOS_NODE_ID;
      msg->destination = destination;
      msg->next_hop = next1;
      msg->data = data;
      if (!radio1Busy) {
        result = call Radio1Send.send(next1, msgBuffer, sizeof(mpdr_msg_t));
        radio1Busy = TRUE;
      } else {
        result = call Radio1Queue.enqueue(msgBuffer);
      }
      if (numRoutes == 2) {
        radio = 2;
      }
    } else {
      msg = call Radio2Send.getPayload(msgBuffer, sizeof(mpdr_msg_t));
      msg->source = TOS_NODE_ID;
      msg->destination = destination;
      msg->next_hop = next2;
      msg->data = data;
      if (!radio2Busy) {
        result = call Radio2Send.send(next2, msgBuffer, sizeof(mpdr_msg_t));
        radio2Busy = TRUE;
      } else {
        result = call Radio2Queue.enqueue(msgBuffer);
      }
      if (numRoutes == 2) {
        radio = 1;
      }
    }
    return result;
  }


  event message_t* Radio1Receive.receive(message_t* msg, void* payload, uint8_t len) {
    mpdr_msg_t* rmsg = (mpdr_msg_t*) payload;
    message_t* msgBuffer;
    mpdr_msg_t* smsg;
    am_addr_t next_hop;
    if (rmsg->destination != TOS_NODE_ID) {
      msgBuffer = call MessagePool.get();
      if (msgBuffer == NULL) {
        dropCount++;
        call SerialLogger.log(82, dropCount);
        return msg;
      }
      smsg = call Radio2Send.getPayload(msgBuffer, sizeof(mpdr_msg_t));
      next_hop = call RoutingTable.getNextHop(rmsg->destination);
      smsg->source = rmsg->source;
      smsg->destination = rmsg->destination;
      smsg->next_hop = next_hop;
      smsg->data = rmsg->data;
      if (!radio2Busy) {
        call Radio2Send.send(next_hop, msgBuffer, sizeof(mpdr_msg_t));
        radio2Busy = TRUE;
      } else {
        call Radio2Queue.enqueue(msgBuffer);
      }
    } else {
      signal MpdrCommunication.receive(rmsg->data, rmsg->source);
    }
    return msg;
  }

  event message_t* Radio2Receive.receive(message_t* msg, void* payload, uint8_t len) {
    mpdr_msg_t* rmsg = (mpdr_msg_t*) payload;
    message_t* msgBuffer;
    mpdr_msg_t* smsg;
    am_addr_t next_hop;
    if (rmsg->destination != TOS_NODE_ID) {
      msgBuffer = call MessagePool.get();
      if (msgBuffer == NULL) {
        dropCount++;
        call SerialLogger.log(83, dropCount);
        return msg;
      }
      smsg = call Radio1Send.getPayload(msgBuffer, sizeof(mpdr_msg_t));
      next_hop = call RoutingTable.getNextHop(rmsg->destination);
      smsg->source = rmsg->source;
      smsg->destination = rmsg->destination;
      smsg->next_hop = next_hop;
      smsg->data = rmsg->data;
      if (!radio2Busy) {
        call Radio1Send.send(next_hop, msgBuffer, sizeof(mpdr_msg_t));
        radio1Busy = TRUE;
      } else {
        call Radio1Queue.enqueue(msgBuffer);
      }
    } else {
      signal MpdrCommunication.receive(rmsg->data, rmsg->source);
    }
    return msg;
  }

  event void Radio1Send.sendDone(message_t* msg, error_t err) {
    mpdr_msg_t* rmsg = call Radio1Send.getPayload(msg, sizeof(mpdr_msg_t));
    signal MpdrCommunication.sendDone(rmsg->data, rmsg->destination, err);
    call MessagePool.put(msg);
    if (call Radio1Queue.empty()) {
      radio1Busy = FALSE;
    } else {
      msg = call Radio1Queue.dequeue();
      rmsg = call Radio1Send.getPayload(msg, sizeof(mpdr_msg_t));
      call Radio1Send.send(rmsg->next_hop, msg, sizeof(mpdr_msg_t));
    }
  }

  event void Radio2Send.sendDone(message_t* msg, error_t err) {
    mpdr_msg_t* rmsg = call Radio2Send.getPayload(msg, sizeof(mpdr_msg_t));
    signal MpdrCommunication.sendDone(rmsg->data, rmsg->destination, err);
    call MessagePool.put(msg);
    if (call Radio2Queue.empty()) {
      radio2Busy = FALSE;
    } else {
      msg = call Radio2Queue.dequeue();
      rmsg = call Radio2Send.getPayload(msg, sizeof(mpdr_msg_t));
      call Radio2Send.send(rmsg->next_hop, msg, sizeof(mpdr_msg_t));
    }
  }

  event void RoutingTable.pathsReady(am_addr_t destination) {
  }

}
