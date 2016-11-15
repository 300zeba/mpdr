#include "TestReceiver.h"

configuration TestReceiverAppC {}
implementation {
  components MainC, TestReceiverC as App, RandomC;
  components new TimerMilliC() as InitTimer;
  components new TimerMilliC() as SendTimer;
  components new TimerMilliC() as FinishTimer;
  App.Boot -> MainC;
  App.Random -> RandomC;
  App.InitTimer -> InitTimer;
  App.SendTimer -> SendTimer;
  App.FinishTimer -> FinishTimer;

  components RF231ActiveMessageC;
  components RF212ActiveMessageC;
  components DualRadioControlC;
  DualRadioControlC.Radio1Control -> RF231ActiveMessageC;
  DualRadioControlC.Radio2Control -> RF212ActiveMessageC;
  App.RadiosControl -> DualRadioControlC;

  App.Radio1Send -> RF231ActiveMessageC.AMSend[24];
  App.Radio2Send -> RF212ActiveMessageC.AMSend[24];
  App.Radio1Receive -> RF231ActiveMessageC.Receive[24];
  App.Radio2Receive -> RF212ActiveMessageC.Receive[24];
  App.ControlSend -> RF212ActiveMessageC.AMSend[25];
  App.ControlReceive -> RF212ActiveMessageC.Receive[25];
  App.Radio1Ack -> RF231ActiveMessageC;
  App.Radio2Ack -> RF212ActiveMessageC;

  components SerialLoggerC;
  App.SerialControl -> SerialLoggerC;
  App.SerialLogger -> SerialLoggerC;
}
