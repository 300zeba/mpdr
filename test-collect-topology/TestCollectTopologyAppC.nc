#include "TestCollectTopology.h"

configuration TestCollectTopologyAppC {}
implementation {
  components MainC, TestCollectTopologyC as App, RandomC;
  App.Boot -> MainC;
  components new TimerMilliC() as NodeTimer;
  App.NodeTimer -> NodeTimer;
  components new TimerMilliC() as RootTimer;
  App.RootTimer -> RootTimer;

  components RF231ActiveMessageC;
  components RF212ActiveMessageC;
  components DualRadioControlC;
  DualRadioControlC.Radio1Control -> RF231ActiveMessageC;
  DualRadioControlC.Radio2Control -> RF212ActiveMessageC;
  App.RadiosControl -> DualRadioControlC;

  components new DualLinkEstimatorP() as Estimator;
  components new TimerMilliC() as EstimatorTimer;
  Estimator.Random -> RandomC;
  Estimator.Radio1Send -> RF231ActiveMessageC.AMSend[24];
  Estimator.Radio2Send -> RF212ActiveMessageC.AMSend[24];
  Estimator.Radio1Receive -> RF231ActiveMessageC.Receive[24];
  Estimator.Radio2Receive -> RF212ActiveMessageC.Receive[24];
  Estimator.Timer -> EstimatorTimer;
  App.EstimatorControl -> Estimator;
  App.Estimator -> Estimator;

  components DisseminationC;
  components new DisseminatorC(uint8_t, 1) as Command;
  App.DisseminationControl -> DisseminationC;
  App.DisseminationCommand -> Command;
  App.CommandUpdate -> Command;

  components CollectionC as Collector;
  components new CollectionSenderC(CL_TEST);
  App.CollectionRoutingControl -> Collector;
  App.CollectionRootControl -> Collector;
  App.CollectionReceive -> Collector.Receive[CL_TEST];
  App.CollectionPacket -> Collector;
  App.CollectionSend -> CollectionSenderC;

  components SerialActiveMessageC;
  components new SerialAMSenderC(0xFF) as SerialSender;
  App.SerialSend -> SerialSender;
  App.SerialControl -> SerialActiveMessageC;

  /*components MpdrP;
  App.Routing -> MpdrP;
  App.MpdrControl -> MpdrP;*/

}
