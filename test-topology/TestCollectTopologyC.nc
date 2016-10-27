#include "TestCollectTopology.h"

module TestCollectTopologyC {
  uses {
    interface Boot;
    interface SplitControl as RadiosControl;

    interface StdControl as EstimatorControl;
    interface DualLinkEstimator as Estimator;

    interface Timer<TMilli> as NodeTimer;
    interface Timer<TMilli> as EstimationTimer;

    interface AMSend as SerialSend;
    interface SplitControl as SerialControl;
  }
}


implementation {

  message_t serialMsgBuffer;
  topology_msg_t* serialMsg;

  uint8_t numNeighbors1;
  uint8_t numNeighbors2;
  uint8_t currentNeighbor1;
  uint8_t currentNeighbor2;

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
      call EstimatorControl.start();
      call EstimationTimer.startOneShot(60000);
    }
  }

  event void RadiosControl.stopDone(error_t err) {}

  event void EstimationTimer.fired() {
    call EstimatorControl.stop();
    numNeighbors1 = call Estimator.getNumOfNeighbors(1);
    numNeighbors2 = call Estimator.getNumOfNeighbors(2);
    currentNeighbor1 = 0;
    currentNeighbor2 = 0;
    serialMsg = (topology_msg_t*) call SerialSend.getPayload(&serialMsgBuffer,
                                                        sizeof(topology_msg_t));
    call NodeTimer.startPeriodic(250);
  }


  event void NodeTimer.fired() {
    uint8_t radio;
    am_addr_t neighbor;
    uint16_t quality;
    if (currentNeighbor1 < numNeighbors1) {
      radio = 1;
      neighbor = call Estimator.getNeighbor(currentNeighbor1, radio);
      quality = call Estimator.getLinkQuality(neighbor, radio);
      currentNeighbor1++;
    } else if (currentNeighbor2 < numNeighbors2) {
      radio = 2;
      neighbor = call Estimator.getNeighbor(currentNeighbor2, radio);
      quality = call Estimator.getLinkQuality(neighbor, radio);
      currentNeighbor2++;
    } else {
      call NodeTimer.stop();
      return;
    }
    serialMsg->source = TOS_NODE_ID;
    serialMsg->neighbor = neighbor;
    serialMsg->radio = radio;
    serialMsg->quality = quality;
    call SerialSend.send(AM_BROADCAST_ADDR, &serialMsgBuffer,
                         sizeof(topology_msg_t));
  }



  event void SerialSend.sendDone(message_t* msg, error_t err) {}

}
