#include "TestCollectTopology.h"

configuration TestCollectTopologyAppC {}
implementation {
  components MainC, TestCollectTopologyC as App, RandomC;
  App.Boot -> MainC;
  components new TimerMilliC() as NodeTimer;
  App.NodeTimer -> NodeTimer;
  components new TimerMilliC() as EstimationTimer;
  App.EstimationTimer -> EstimationTimer;

  components RF231ActiveMessageC;
  components RF212ActiveMessageC;
  components DualRadioControlC;
  DualRadioControlC.Radio1Control -> RF231ActiveMessageC;
  DualRadioControlC.Radio2Control -> RF212ActiveMessageC;
  App.RadiosControl -> DualRadioControlC;

  components new DualLinkEstimatorP() as Estimator;
  components new TimerMilliC() as EstimatorTimer1;
  components new TimerMilliC() as EstimatorTimer2;
  Estimator.Random -> RandomC;
  Estimator.Radio1Send -> RF231ActiveMessageC.AMSend[24];
  Estimator.Radio2Send -> RF212ActiveMessageC.AMSend[24];
  Estimator.Radio1Receive -> RF231ActiveMessageC.Receive[24];
  Estimator.Radio2Receive -> RF212ActiveMessageC.Receive[24];
  Estimator.Radio1Timer -> EstimatorTimer1;
  Estimator.Radio2Timer -> EstimatorTimer2;
  App.EstimatorControl -> Estimator;
  App.Estimator -> Estimator;

  components SerialActiveMessageC;
  components new SerialAMSenderC(0xFF) as SerialSender;
  App.SerialSend -> SerialSender;
  App.SerialControl -> SerialActiveMessageC;

}
