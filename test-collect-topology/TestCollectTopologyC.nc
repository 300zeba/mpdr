#include "TestCollectTopology.h"

module TestCollectTopologyC {
  uses {
    interface Boot;
    interface SplitControl as RadiosControl;

    interface StdControl as CollectionRoutingControl;
    interface RootControl as CollectionRootControl;
    interface Receive as CollectionReceive;
    interface CollectionPacket;
    interface Send as CollectionSend;

    interface StdControl as DisseminationControl;
    interface DisseminationValue<uint8_t> as DisseminationCommand;
    interface DisseminationUpdate<uint8_t> as CommandUpdate;

    interface StdControl as EstimatorControl;
    interface DualLinkEstimator as Estimator;

    interface Timer<TMilli> as NodeTimer;
    interface Timer<TMilli> as RootTimer;

    interface AMSend as SerialSend;
    interface SplitControl as SerialControl;
    //interface MpdrRouting as Routing;
    //interface StdControl as MpdrControl;
  }
}


implementation {

  network_t network;
  uint8_t neighbors_size_1;
  uint8_t neighbors_size_2;
  uint8_t current_radio;
  uint8_t current_neighbor;

  message_t topMsgBuffer;
  message_t serialMsgBuffer;
  topology_msg_t* topMsg;
  topology_msg_t* serialMsg;

  uint8_t root_counter = 0;

  void initNetwork() {
    uint8_t i;
    network.num_of_nodes = 0;
    for (i = 0; i < MAX_NODES; i++) {
      network.nodes[i].address = INVALID_ADDR;
      network.nodes[i].num_of_neighbors = 0;
    }
  }

  event void Boot.booted() {
    dbg("Control", "Booted\n");
    initNetwork();
    call SerialControl.start();

  }

  event void SerialControl.startDone(error_t err) {
    if (err != SUCCESS) {
      call SerialControl.start();
    } else {
      dbg("Control", "Serial started\n");
      call RadiosControl.start();
    }
  }

  event void SerialControl.stopDone(error_t err) {
    dbg("Control", "Serial stopped\n");
  }

  event void RadiosControl.startDone(error_t err) {
    if (err != SUCCESS) {
      dbg("Control", "ERROR starting radios\n");
      call RadiosControl.start();
    } else {
      dbg("Control", "Radios started\n");
      call DisseminationControl.start();
      call CollectionRoutingControl.start();
      //call MpdrControl.start();
      if (TOS_NODE_ID % 500 == 1) {
        call CollectionRootControl.setRoot();
        call RootTimer.startOneShot(10000);
      }
    }
  }

  event void RadiosControl.stopDone(error_t err) {
    dbg("Control", "Radios stopped\n");
  }

  event message_t* CollectionReceive.receive(message_t* msg, void* payload, uint8_t len) {
    dbg("Collection", "Received collected message\n");
    topMsg = (topology_msg_t*) payload;
    serialMsg = call SerialSend.getPayload(&serialMsgBuffer, sizeof(topology_msg_t));
    serialMsg->source = topMsg->source;
    serialMsg->neighbor = topMsg->neighbor;
    serialMsg->radio = topMsg->radio;
    serialMsg->quality = topMsg->quality;
    call SerialSend.send(AM_BROADCAST_ADDR, &serialMsgBuffer, sizeof(topology_msg_t));
    return msg;
  }

  event void CollectionSend.sendDone(message_t* m, error_t err) {
    dbg("Collection", "Send completed.\n");
  }

  event void DisseminationCommand.changed() {
    uint8_t val;
    const uint8_t* newVal = call DisseminationCommand.get();
    val = *newVal;
    if (val == 1) {
      call EstimatorControl.start();
    }
    if (val == 2) {
      call EstimatorControl.stop();
    }
    if (val == 3) {
      if (!(call CollectionRootControl.isRoot())) {
        neighbors_size_1 = call Estimator.getNumOfNeighbors(1);
        neighbors_size_2 = call Estimator.getNumOfNeighbors(2);
        current_radio = 1;
        current_neighbor = 0;
        call NodeTimer.startPeriodic(2000);
      }
    }
  }

  event void NodeTimer.fired() {
    uint8_t neighbors_size;
    if (current_radio == 1) {
      neighbors_size = neighbors_size_1;
    } else {
      neighbors_size = neighbors_size_2;
    }
    if (current_neighbor < neighbors_size) {
      topMsg = call CollectionSend.getPayload(&topMsgBuffer, sizeof(topology_msg_t));
      topMsg->source = TOS_NODE_ID;
      topMsg->neighbor = call Estimator.getNeighbor(current_neighbor, current_radio);
      topMsg->radio = current_radio;
      topMsg->quality = call Estimator.getLinkQuality(topMsg->neighbor, current_radio);
      call CollectionSend.send(&topMsgBuffer, sizeof(topology_msg_t));
    } else {
      if (current_radio == 1) {
        current_radio = 2;
        current_neighbor = 0;
        return;
      } else {
        call NodeTimer.stop();
      }
    }
    current_neighbor++;
  }

  event void RootTimer.fired() {
    root_counter++;
    call CommandUpdate.change(&root_counter);
    if (root_counter == 1) {
      call RootTimer.startOneShot(60000);
    }
    if (root_counter == 2) {
      call RootTimer.startOneShot(10000);
    }
    if (root_counter == 3) {
      root_counter = 0;
    }
  }

  event void SerialSend.sendDone(message_t* msg, error_t err) {

  }

  /*event void Routing.pathsReady(am_addr_t destination) {

  }*/

}
