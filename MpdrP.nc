
configuration MpdrP {
  provides {
    interface StdControl;
    interface MpdrRouting;
    interface MpdrCommunication;
  }
}

implementation {
  components new MpdrForwardingEngineP() as Forwarder;
  StdControl = Forwarder;
  MpdrCommunication = Forwarder;

  components new MpdrRoutingEngineP() as Router;
  StdControl = Router;
  MpdrRouting = Router;

  components RF231ActiveMessageC;
  components RF212ActiveMessageC;

  Forwarder.RoutingTable -> Router;
  Forwarder.Radio1Send -> RF231ActiveMessageC.AMSend[22];
  Forwarder.Radio2Send -> RF212ActiveMessageC.AMSend[22];
  Forwarder.Radio1Receive -> RF231ActiveMessageC.Receive[22];
  Forwarder.Radio2Receive -> RF212ActiveMessageC.Receive[22];

  components new PoolC(message_t, 100);
  components new QueueC(message_t*, 100) as Radio1Queue;
  components new QueueC(message_t*, 100) as Radio2Queue;

  Forwarder.MessagePool -> PoolC;
  Forwarder.Radio1Queue -> Radio1Queue;
  Forwarder.Radio2Queue -> Radio2Queue;

  Router.RoutingSend -> RF231ActiveMessageC.AMSend[23];
  Router.RoutingAck -> RF231ActiveMessageC;
  Router.RoutingReceive -> RF231ActiveMessageC.Receive[23];

  components SerialLoggerC;
  Router.SerialLogger -> SerialLoggerC;
  Forwarder.SerialLogger-> SerialLoggerC;
}
