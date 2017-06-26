#include "Mpdr.h"
#include "../serial-logger/SerialLogger.h"

generic module MpdrRoutingEngineP() {
  provides {
    interface StdControl;
    interface MpdrRouting;
  }
  uses {
    interface AMSend as RoutingSend1;
    interface AMSend as RoutingSend2;
    interface Receive as RoutingReceive1;
    interface Receive as RoutingReceive2;

    interface AMSend as FindSend1;
    interface AMSend as FindSend2;
    interface Receive as FindReceive1;
    interface Receive as FindReceive2;

    interface AMSend as TraceSend1;
    interface AMSend as TraceSend2;
    interface Receive as TraceReceive1;
    interface Receive as TraceReceive2;

    interface RadioChannel as RadioChannel1;
    interface RadioChannel as RadioChannel2;
    interface PacketAcknowledgements as RoutingAck;
    interface SerialLogger;

    interface Timer<TMilli> as TraceTimer;
  }
}

implementation {

  mpdr_routing_table_t fwdTable;
  mpdr_routing_table_t sendTable;
  message_t msgBuffer;
  message_t msg1;
  message_t msg2;
  uint8_t received = 0;
  bool received1 = FALSE;
  bool received2 = FALSE;
  uint8_t numRoutes = 2;

  uint16_t current_iteration = 0;
  mpdr_type_t type;
  uint16_t dist[2];
  am_addr_t next[2];
  am_addr_t prev[2];
  am_addr_t FN_phcr[2];
  uint16_t FN_dist[2];
  am_addr_t FHB_phcr[2];
  uint16_t FHB_dist[2];
  am_addr_t OHB_phcr[2];
  uint16_t OHB_dist[2];

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
        if (sendTable.items[i].radio == 1) {
          *addr1 = sendTable.items[i].next_hop;
        } else {
          *addr2 = sendTable.items[i].next_hop;
        }
        found++;
        if (numRoutes == found) {
          return SUCCESS;
        }
      }
    }
    return FAIL;
  }

  command void MpdrRouting.setNumPaths(uint8_t num_paths) {
    numRoutes = num_paths;
  }

  command uint8_t MpdrRouting.getNumPaths() {
    return numRoutes;
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
          sendTable.items[i].next_hop == next_hop &&
          destination != next_hop) {
        return TRUE;
      }
    }
    return FALSE;
  }

  error_t addFwdRoute(am_addr_t source, am_addr_t destination,
                      am_addr_t next_hop, uint8_t radio, uint8_t channel) {
    if (fwdTable.size >= MAX_MPDR_TABLE_SIZE) {
      return FAIL;
    }
    if (inFwdTable(source, destination, next_hop)) {
      return FAIL;
    }
    fwdTable.items[fwdTable.size].source = source;
    fwdTable.items[fwdTable.size].destination = destination;
    fwdTable.items[fwdTable.size].next_hop = next_hop;
    fwdTable.items[fwdTable.size].radio = radio;
    fwdTable.items[fwdTable.size].channel = channel;
    fwdTable.size++;
    return SUCCESS;
  }

  error_t addSendRoute(am_addr_t source, am_addr_t destination,
                       am_addr_t next_hop, uint8_t radio, uint8_t channel) {
    if (sendTable.size >= MAX_MPDR_TABLE_SIZE) {
      return FAIL;
    }
    if (inSendTable(source, destination, next_hop)) {
      return FAIL;
    }
    sendTable.items[sendTable.size].source = source;
    sendTable.items[sendTable.size].destination = destination;
    sendTable.items[sendTable.size].next_hop = next_hop;
    sendTable.items[sendTable.size].radio = radio;
    sendTable.items[sendTable.size].channel = channel;
    sendTable.size++;
    return SUCCESS;
  }

  command error_t MpdrRouting.addRoutingItem(am_addr_t source,
                                             am_addr_t destination,
                                             am_addr_t next_hop, uint8_t radio,
                                             uint8_t channel) {
    return addFwdRoute(source, destination, next_hop, radio, channel);
  }

  command error_t MpdrRouting.addSendRoute(am_addr_t source,
                                           am_addr_t destination,
                                           am_addr_t next_hop, uint8_t radio,
                                           uint8_t channel) {
    return addSendRoute(source, destination, next_hop, radio, channel);
  }

  command error_t MpdrRouting.setRadioChannel(uint8_t radio, uint8_t channel) {
    uint8_t channels[2][4] = {{26, 15, 25, 20}, {6, 10, 4, 8}};
    uint8_t chosen = channels[radio-1][channel-1];
    error_t result;
    uint8_t attempts = 0;
    if (radio != 1 && radio != 2) {
      call SerialLogger.log(LOG_RADIO_NUMBER_ERROR, radio);
      return FAIL;
    }
    if (channel == 0 || channel > 4) {
      call SerialLogger.log(LOG_CHANNEL_NUMBER_ERROR, channel);
      return FAIL;
    }
    if (radio == 1) {
      /*call SerialLogger.log(LOG_SET_RADIO_CHANNEL_1, chosen);*/
      result = FAIL;
      while (result != SUCCESS && attempts < 300) {
        result = call RadioChannel1.setChannel(chosen);
        if (result == EALREADY) {
          /*call SerialLogger.log(LOG_SET_RADIO_CHANNEL_1_OK, chosen);*/
          result = SUCCESS;
        }
        if (result != SUCCESS && attempts < 3) {
          /*call SerialLogger.log(LOG_SET_RADIO_CHANNEL_1_ERROR, result);*/
        }
        attempts++;
      }
    } else {
      /*call SerialLogger.log(LOG_SET_RADIO_CHANNEL_2, chosen);*/
      result = FAIL;
      while (result != SUCCESS && attempts < 100) {
        result = call RadioChannel2.setChannel(chosen);
        if (result == EALREADY) {
          /*call SerialLogger.log(LOG_SET_RADIO_CHANNEL_2_OK, chosen);*/
          result = SUCCESS;
        }
        if (result != SUCCESS && attempts < 300) {
          /*call SerialLogger.log(LOG_SET_RADIO_CHANNEL_2_ERROR, result);*/
        }
      }
    }
    if (attempts >= 300) {
      call SerialLogger.log(LOG_CHANGE_CHANNEL_ATTEMPTS, attempts);
    }
    return result;
  }

  command error_t MpdrRouting.sendRouteMsg(am_addr_t source,
                                           am_addr_t destination,
                                           uint8_t path_id, uint8_t size,
                                           am_addr_t* items) {
    uint8_t i;
    am_addr_t next_hop;
    mpdr_routing_msg_t* rmsg = call RoutingSend1.getPayload(&msgBuffer,
                                                    sizeof(mpdr_routing_msg_t));
    error_t result;
    rmsg->source = source;
    rmsg->destination = destination;
    rmsg->last_hop = TOS_NODE_ID;
    rmsg->path_id = path_id;
    if (size > 0) {
      next_hop = items[0];
    } else {
      next_hop = source;
    }
    rmsg->next_hop = next_hop;
    if (size > 0) {
      size--;
    }
    rmsg->size = size;
    for (i = 0; i < size; i++) {
      rmsg->items[i] = items[i+1];
    }
    if (path_id == 1) {
      rmsg->last_radio = 1;
      rmsg->last_channel = 1;
    } else {
      rmsg->last_radio = 2;
      rmsg->last_channel = 2;
    }
    call RoutingAck.requestAck(&msgBuffer);
    if (rmsg->last_radio == 1) {
      result = call RoutingSend1.send(next_hop, &msgBuffer,
                                      sizeof(mpdr_routing_msg_t));
    } else {
      result = call RoutingSend2.send(next_hop, &msgBuffer,
                                      sizeof(mpdr_routing_msg_t));
    }

    return result;
  }

  void receivedRoutingMsg(message_t* msg, void* payload, uint8_t len) {
    mpdr_routing_msg_t* rmsg = (mpdr_routing_msg_t*) payload;
    mpdr_routing_msg_t* smsg = call RoutingSend1.getPayload(&msgBuffer,
                                                    sizeof(mpdr_routing_msg_t));
    am_addr_t next_hop;
    uint8_t i;
    uint8_t channel;

    call SerialLogger.log(LOG_RCV_ROUTING_LAST_HOP, rmsg->last_hop);
    call SerialLogger.log(LOG_RCV_ROUTING_LAST_RADIO, rmsg->last_radio);
    call SerialLogger.log(LOG_RCV_ROUTING_LAST_CHANNEL, rmsg->last_channel);

    if (rmsg->last_radio == 1) {
      channel = (rmsg->last_channel == 1) ? 26 : 15;
      /*call SerialLogger.log(LOG_SET_RADIO_CHANNEL_1, channel);*/
      call RadioChannel1.setChannel(channel);
    } else {
      channel = (rmsg->last_channel == 1) ? 6 : 10;
      /*call SerialLogger.log(LOG_SET_RADIO_CHANNEL_2, channel);*/
      call RadioChannel2.setChannel(channel);
    }
    if (rmsg->source == TOS_NODE_ID) {
      if (rmsg->path_id == 1) {
        received1 = TRUE;
      }
      if (rmsg->path_id == 2) {
        received2 = TRUE;
      }
      received++;
      // call SerialLogger.log(21, rmsg->last_hop);
      addSendRoute(rmsg->source, rmsg->destination, rmsg->last_hop,
                   rmsg->last_radio, rmsg->last_channel);
      if (((numRoutes == 1) && (received1 || received2)) ||
          ((numRoutes == 2) && received1 && received2)) {
        signal MpdrRouting.pathsReady(rmsg->destination);
      }
    } else {
      // call SerialLogger.log(22, rmsg->last_hop);
      addFwdRoute(rmsg->source, rmsg->destination, rmsg->last_hop,
                  rmsg->last_radio, rmsg->last_channel);
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
      if (rmsg->last_radio == 1) {
        smsg->last_radio = 2;
      } else {
        smsg->last_radio = 1;
      }
      if (rmsg->path_id == 1) {
        if (rmsg->last_radio == 2) {
          smsg->last_channel = (rmsg->last_channel == 1) ? 2 : 1;
        } else {
          smsg->last_channel = rmsg->last_channel;
        }
      } else {
        if (rmsg->last_radio == 1) {
          smsg->last_channel = (rmsg->last_channel == 1) ? 2 : 1;
        } else {
          smsg->last_channel = rmsg->last_channel;
        }
      }
      call RoutingAck.requestAck(&msgBuffer);
      if (smsg->last_radio == 1) {
        call RoutingSend1.send(next_hop, &msgBuffer, sizeof(mpdr_routing_msg_t));
      } else {
        call RoutingSend2.send(next_hop, &msgBuffer, sizeof(mpdr_routing_msg_t));
      }
    }
  }

  void beginIteration(uint16_t iteration) {
    current_iteration = iteration;
    if (iteration == 1 || iteration == 3) {
      type = FREE;
      next[0] = INVALID_ADDR;
      next[1] = INVALID_ADDR;
      prev[0] = INVALID_ADDR;
      prev[1] = INVALID_ADDR;
    }
    FN_phcr[0] = INVALID_ADDR;
    FN_phcr[1] = INVALID_ADDR;
    FN_dist[0] = INFINITE_VALUE;
    FN_dist[1] = INFINITE_VALUE;
    FHB_phcr[0] = INVALID_ADDR;
    FHB_phcr[1] = INVALID_ADDR;
    FHB_dist[0] = INFINITE_VALUE;
    FHB_dist[1] = INFINITE_VALUE;
    OHB_phcr[0] = INVALID_ADDR;
    OHB_phcr[1] = INVALID_ADDR;
    OHB_dist[0] = INFINITE_VALUE;
    OHB_dist[1] = INFINITE_VALUE;
  }

  uint16_t getEdgeWeight(am_addr_t neighbor) {
    // TODO: implement the function to get the edge weight.
    return 1;
  }

  void sendFindMessage(am_addr_t source, am_addr_t destination,
                       am_addr_t next_hop, uint8_t radio, uint16_t distance) {
    mpdr_find_msg_t* smsg;
    error_t result;
    if (radio == 0) {
      smsg = call FindSend1.getPayload(&msg1, sizeof(mpdr_find_msg_t));
    } else {
      smsg = call FindSend2.getPayload(&msg2, sizeof(mpdr_find_msg_t));
    }
    smsg->source = source;
    smsg->destination = destination;
    smsg->last_hop = TOS_NODE_ID;
    smsg->iteration = current_iteration;
    smsg->distance = distance;
    if (radio == 0) {
      result = call FindSend1.send(next_hop, &msg1, sizeof(mpdr_find_msg_t));
    } else {
      result = call FindSend2.send(next_hop, &msg2, sizeof(mpdr_find_msg_t));
    }
  }

  void sendTraceMessage(am_addr_t source, am_addr_t destination,
                        am_addr_t next_hop, uint8_t radio, uint16_t distance) {
    mpdr_trace_msg_t* smsg;
    error_t result;
    if (radio == 0) {
      smsg = call TraceSend1.getPayload(&msg1, sizeof(mpdr_trace_msg_t));
    } else {
      smsg = call TraceSend2.getPayload(&msg2, sizeof(mpdr_trace_msg_t));
    }
    smsg->source = source;
    smsg->destination = destination;
    smsg->last_hop = TOS_NODE_ID;
    smsg->iteration = current_iteration;
    smsg->distance = distance;
    if (radio == 0) {
      result = call TraceSend1.send(next_hop, &msg1, sizeof(mpdr_trace_msg_t));
    } else {
      result = call TraceSend2.send(next_hop, &msg2, sizeof(mpdr_trace_msg_t));
    }
  }

  bool inPrev(am_addr_t node) {
    return (node == prev[0] || node == prev[1]);
  }

  bool inNext(am_addr_t node) {
    return (node == next[0] || node == next[1]);
  }

  void receivedFindMsg(message_t* msg, void* payload, uint8_t len,
                       uint8_t radio) {
    mpdr_find_msg_t* rmsg = (mpdr_find_msg_t*) payload;
    am_addr_t source = rmsg->source;
    am_addr_t destination = rmsg->destination;
    am_addr_t last_hop = rmsg->last_hop;
    uint16_t iteration = rmsg->iteration;
    uint16_t distance = rmsg->distance;
    uint16_t weight = getEdgeWeight(last_hop);
    uint8_t send_radio = (radio + 1) % 2;
    if (current_iteration != iteration) {
      beginIteration(iteration);
    }
    if (TOS_NODE_ID == rmsg->source) {
      return;
    }
    if (type == FREE) {
      dist[radio] = distance + weight;
      if (dist[radio] < FN_dist[radio]) {
        FN_phcr[radio] = last_hop;
        FN_dist[radio] = dist[radio];
        sendFindMessage(source, destination, AM_BROADCAST_ADDR, send_radio,
                        dist[radio]);
      }
    } else if (type == OCCUPIED && !inPrev(last_hop) && !inNext(last_hop)) {
      dist[radio] = distance + weight;
      if (dist[radio] < FHB_dist[radio]) {
        FHB_phcr[radio] = last_hop;
        FHB_dist[radio] = dist[radio];
        if (TOS_NODE_ID != destination) {
          sendFindMessage(source, destination, prev[0], send_radio,
                          dist[radio]);
        }
      }
    } else if (type == OCCUPIED && inNext(last_hop)) {
      dist[radio] = distance - weight;
      if (dist[radio] < OHB_dist[radio]) {
        OHB_phcr[radio] = last_hop;
        OHB_dist[radio] = dist[radio];
        sendFindMessage(source, destination, AM_BROADCAST_ADDR, send_radio,
                        dist[radio]);
      }
    }
  }

  void receivedTraceMsg(message_t* msg, void* payload, uint8_t len, uint8_t radio) {
    mpdr_trace_msg_t* rmsg = (mpdr_trace_msg_t*) payload;
    am_addr_t source = rmsg->source;
    am_addr_t destination = rmsg->destination;
    am_addr_t last_hop = rmsg->last_hop;
    uint16_t iteration = rmsg->iteration;
    uint16_t distance = rmsg->distance;
    uint8_t send_radio = (radio + 1) % 2;
    if (TOS_NODE_ID == source) {
      if (type == FREE) {
        type = OCCUPIED;
        next[0] = last_hop;
      } else {
        next[1] = last_hop;
      }
    } else if (type == FREE) {
      type = OCCUPIED;
      next[0] = last_hop;
      prev[0] = FN_phcr[send_radio];
      sendTraceMessage(source, destination, FN_phcr[send_radio], send_radio,
                       distance);
    } else if (type == OCCUPIED && !inPrev(last_hop)) {
      next[0] = last_hop;
      sendTraceMessage(source, destination, OHB_phcr[send_radio], send_radio,
                       distance);
    } else if (type == OCCUPIED && inPrev(last_hop)
               && FHB_dist[send_radio] > OHB_dist[send_radio]) {
      type = FREE;
      prev[0] = INVALID_ADDR;
      next[0] = INVALID_ADDR;
      sendTraceMessage(source, destination, OHB_phcr[send_radio], send_radio,
                       distance);
    } else if (type == OCCUPIED && inPrev(last_hop)
               && FHB_dist[send_radio] <= OHB_dist[send_radio]) {
      prev[0] = FHB_phcr[send_radio];
    }
  }

  event message_t* RoutingReceive1.receive(message_t* msg, void* payload, uint8_t len) {
    receivedRoutingMsg(msg, payload, len);
    return msg;
  }

  event message_t* RoutingReceive2.receive(message_t* msg, void* payload, uint8_t len) {
    receivedRoutingMsg(msg, payload, len);
    return msg;
  }

  event message_t* FindReceive1.receive(message_t* msg, void* payload, uint8_t len) {
    receivedFindMsg(msg, payload, len, 0);
    return msg;
  }

  event message_t* FindReceive2.receive(message_t* msg, void* payload, uint8_t len) {
    receivedFindMsg(msg, payload, len, 1);
    return msg;
  }

  event message_t* TraceReceive1.receive(message_t* msg, void* payload, uint8_t len) {
    receivedTraceMsg(msg, payload, len, 0);
    return msg;
  }

  event message_t* TraceReceive2.receive(message_t* msg, void* payload, uint8_t len) {
    receivedTraceMsg(msg, payload, len, 1);
    return msg;
  }

  command void MpdrRouting.startFinding(am_addr_t destination) {
    current_iteration = 1;
    sendFindMessage(TOS_NODE_ID, destination, AM_BROADCAST_ADDR, 0, 0);
  }

  event void RoutingSend1.sendDone(message_t* msg, error_t error) {
    mpdr_routing_msg_t* rmsg = call RoutingSend1.getPayload(msg, sizeof(mpdr_routing_msg_t));
    uint8_t channel;
    if (error != SUCCESS) {
      call SerialLogger.log(LOG_SEND_1_ERROR, error);
      call RoutingSend1.send(rmsg->next_hop, msg, sizeof(mpdr_routing_msg_t));
    } else {
      channel = (rmsg->last_channel == 1) ? 26 : 15;
      /*call SerialLogger.log(LOG_SET_RADIO_CHANNEL_1, channel);*/
      call RadioChannel1.setChannel(channel);
    }
  }

  event void RoutingSend2.sendDone(message_t* msg, error_t error) {
    mpdr_routing_msg_t* rmsg = call RoutingSend2.getPayload(msg, sizeof(mpdr_routing_msg_t));
    uint8_t channel;
    if (error != SUCCESS) {
      call SerialLogger.log(LOG_SEND_2_ERROR, error);
      call RoutingSend2.send(rmsg->next_hop, msg, sizeof(mpdr_routing_msg_t));
    } else {
      channel = (rmsg->last_channel == 1) ? 6 : 10;
      /*call SerialLogger.log(LOG_SET_RADIO_CHANNEL_2, channel);*/
      call RadioChannel2.setChannel(channel);
    }
  }

  event void FindSend1.sendDone(message_t* msg, error_t error) {

  }

  event void FindSend2.sendDone(message_t* msg, error_t error) {

  }

  event void TraceSend1.sendDone(message_t* msg, error_t error) {

  }

  event void TraceSend2.sendDone(message_t* msg, error_t error) {

  }

  event void RadioChannel1.setChannelDone() {
    /*uint8_t channel = call RadioChannel1.getChannel();
    call SerialLogger.log(LOG_SET_RADIO_CHANNEL_1_OK, channel);*/
  }

  event void RadioChannel2.setChannelDone() {
    /*uint8_t channel = call RadioChannel2.getChannel();
    call SerialLogger.log(LOG_SET_RADIO_CHANNEL_2_OK, channel);*/
  }

}
