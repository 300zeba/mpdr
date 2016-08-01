#include "SerialLogger.h"

configuration SerialLoggerC {
  provides {
    interface SplitControl;
    interface SerialLogger;
  }
}

implementation {
  components SerialLoggerP;
  components SerialActiveMessageC;
  components new SerialAMSenderC(0xFF) as SerialSenderC;
  components new TimerMilliC() as SerialTimerC;
  components new PoolC(message_t, 100) as SerialPoolC;
  components new QueueC(message_t*, 100) as SerialQueueC;

  SerialLoggerP.SerialControl -> SerialActiveMessageC;
  SerialLoggerP.SerialSend -> SerialSenderC;
  SerialLoggerP.Timer -> SerialTimerC;
  SerialLoggerP.Pool -> SerialPoolC;
  SerialLoggerP.Queue -> SerialQueueC;

  SplitControl = SerialLoggerP;
  SerialLogger = SerialLoggerP;
}
