#include "Mpdr.h"

generic module MpdrRoutingEngineP() {
  provides {
    interface StdControl;
    interface MpdrRouting;
  }
  uses {
    interface AMSend as RoutingSend;
    interface Receive as RoutingReceive;
    interface PacketAcknowledgements as RoutingAck;
    interface SerialLogger;
  }
}

implementation {

  mpdr_routing_table_t fwdTable;
  mpdr_routing_table_t sendTable;
  message_t msgBuffer;
  uint8_t received = 0;
  bool received1 = FALSE;
  bool received2 = FALSE;
  uint8_t numRoutes = 2;

  void initTables() {
    fwdTable.size = 0;
    sendTable.size = 0;
  }

  command error_t StdControl.start() {
    dbg("StdControl", "MpdrRoutingEngineP started\n");
    initTables();
    return SUCCESS;
  }

  command error_t StdControl.stop() {
    dbg("StdControl", "MpdrRoutingEngineP stopped\n");
    return SUCCESS;
  }

  command am_addr_t MpdrRouting.getNextHop(am_addr_t destination) {
    uint8_t i;
    for (i = 0; i < fwdTable.size; i++) {
      if (fwdTable.items[i].destination == destination) {
        return fwdTable.items[i].next_hop;
      }
    }
    return INVALID_ADDR;
  }

  command error_t MpdrRouting.getSendAddresses(am_addr_t destination, am_addr_t* addr1, am_addr_t* addr2) {
    uint8_t i, found;
    found = 0;
    for (i = 0; i < sendTable.size; i++) {
      if (sendTable.items[i].destination == destination) {
        if (found == 0) {
          *addr1 = sendTable.items[i].next_hop;
          found++;
          if (numRoutes == 1) {
            return SUCCESS;
          }
        } else {
          *addr2 = sendTable.items[i].next_hop;
          return SUCCESS;
        }
      }
    }
    return FAIL;
  }

  command void MpdrRouting.setNumRoutes(uint8_t num_paths) {
    numRoutes = num_paths;
  }

  bool inFwdTable(am_addr_t source, am_addr_t destination, am_addr_t next_hop) {
    uint8_t i;
    for (i = 0; i < fwdTable.size; i++) {
      if (fwdTable.items[i].source == source &&
          fwdTable.items[i].destination == destination &&
          fwdTable.items[i].next_hop == next_hop) {
        return TRUE;
      }
    }
    return FALSE;
  }

  bool inSendTable(am_addr_t source, am_addr_t destination, am_addr_t next_hop) {
    uint8_t i;
    for (i = 0; i < sendTable.size; i++) {
      if (sendTable.items[i].source == source &&
          sendTable.items[i].destination == destination &&
          sendTable.items[i].next_hop == next_hop) {
        return TRUE;
      }
    }
    return FALSE;
  }

  error_t addFwdRoute(am_addr_t source, am_addr_t destination, am_addr_t next_hop) {
    if (fwdTable.size >= MAX_MPDR_TABLE_SIZE) {
      return FAIL;
    }
    if (inFwdTable(source, destination, next_hop)) {
      return FAIL;
    }
    fwdTable.items[fwdTable.size].source = source;
    fwdTable.items[fwdTable.size].destination = destination;
    fwdTable.items[fwdTable.size].next_hop = next_hop;
    fwdTable.size++;
    return SUCCESS;
  }

  error_t addSendRoute(am_addr_t source, am_addr_t destination, am_addr_t next_hop) {
    if (sendTable.size >= MAX_MPDR_TABLE_SIZE) {
      return FAIL;
    }
    if (inSendTable(source, destination, next_hop)) {
      return FAIL;
    }
    sendTable.items[sendTable.size].source = source;
    sendTable.items[sendTable.size].destination = destination;
    sendTable.items[sendTable.size].next_hop = next_hop;
    sendTable.size++;
    return SUCCESS;
  }

  command error_t MpdrRouting.addRoutingItem(am_addr_t source, am_addr_t destination, am_addr_t next_hop) {
    return addFwdRoute(source, destination, next_hop);
  }

  command error_t MpdrRouting.sendRouteMsg(am_addr_t source, am_addr_t destination,
                                                uint8_t path_id, uint8_t size,
                                                am_addr_t* items) {
    uint8_t i;
    am_addr_t next_hop;
    mpdr_routing_msg_t* rmsg = call RoutingSend.getPayload(&msgBuffer, sizeof(mpdr_routing_msg_t));
    error_t result;
    rmsg->source = source;
    rmsg->destination = destination;
    rmsg->last_hop = TOS_NODE_ID;
    rmsg->path_id = path_id;
    next_hop = items[0];
    rmsg->next_hop = next_hop;
    if (size > 0) {
      size--;
    }
    rmsg->size = size;
    for (i = 0; i < size; i++) {
      rmsg->items[i] = items[i+1];
    }
    call RoutingAck.requestAck(&msgBuffer);
    //call SerialLogger.log(51, next_hop);
    result = call RoutingSend.send(next_hop, &msgBuffer, sizeof(mpdr_routing_msg_t));
    //call SerialLogger.log(52, result);
    return result;
  }

  event message_t* RoutingReceive.receive(message_t* msg, void* payload, uint8_t len) {
    mpdr_routing_msg_t* rmsg = (mpdr_routing_msg_t*) payload;
    mpdr_routing_msg_t* smsg = call RoutingSend.getPayload(&msgBuffer, sizeof(mpdr_routing_msg_t));
    am_addr_t next_hop;
    uint8_t i;
    if (rmsg->source == TOS_NODE_ID) {
      if (rmsg->path_id == 1) {
        received1 = TRUE;
      }
      if (rmsg->path_id == 2) {
        received2 = TRUE;
      }
      received++;
      call SerialLogger.log(55, received);
      call SerialLogger.log(56, rmsg->last_hop);
      addSendRoute(rmsg->source, rmsg->destination, rmsg->last_hop);
      if (((numRoutes == 1) && (received1 || received2)) || ((numRoutes == 2) && received1 && received2)) {
        signal MpdrRouting.pathsReady(rmsg->destination);
      }
    } else {
      call SerialLogger.log(54, rmsg->last_hop);
      addFwdRoute(rmsg->source, rmsg->destination, rmsg->last_hop);
      if (rmsg->size > 0) {
        next_hop = rmsg->items[0];
      } else {
        next_hop = rmsg->source;
      }
      smsg->source = rmsg->source;
      smsg->destination = rmsg->destination;
      smsg->last_hop = TOS_NODE_ID;
      smsg->next_hop = next_hop;
      smsg->path_id = rmsg->path_id;
      if (rmsg->size > 0) {
        smsg->size = rmsg->size - 1;
      } else {
        smsg->size = 0;
      }
      for (i = 0; i < smsg->size; i++) {
        smsg->items[i] = rmsg->items[i+1];
      }
      call RoutingAck.requestAck(&msgBuffer);
      call RoutingSend.send(next_hop, &msgBuffer, sizeof(mpdr_routing_msg_t));
    }
    return msg;
  }

  event void RoutingSend.sendDone(message_t* msg, error_t error) {
    mpdr_routing_msg_t* rmsg = call RoutingSend.getPayload(msg, sizeof(mpdr_routing_msg_t));
    if (error != SUCCESS) {
      call SerialLogger.log(53, rmsg->next_hop);
      call SerialLogger.log(57, error);
      call RoutingSend.send(rmsg->next_hop, msg, sizeof(mpdr_routing_msg_t));
    } else {
      call SerialLogger.log(50, rmsg->next_hop);
    }
  }
//FIX
}
