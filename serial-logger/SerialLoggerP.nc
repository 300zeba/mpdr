#include "SerialLogger.h"
#include "Timer.h"

module SerialLoggerP {
  provides {
    interface SplitControl;
    interface SerialLogger;
  }
  uses {
    interface SplitControl as SerialControl;
    interface AMSend as SerialSend;
    interface Timer<TMilli>;
    interface Pool<message_t>;
    interface Queue<message_t*>;
  }
}

implementation {

  bool serialBusy = FALSE;

  /*command error_t StdControl.start() {
    call Timer.startPeriodic(SERIAL_TIMER_PERIOD_MILLI);
    return SUCCESS;
  }

  command error_t StdControl.stop() {
    call Timer.stop();
    return SUCCESS;
  }*/

  command error_t SplitControl.start() {
    return call SerialControl.start();
  }

  event void SerialControl.startDone(error_t error) {
    if (error == SUCCESS) {
      call Timer.startPeriodic(SERIAL_TIMER_PERIOD_MILLI);
    }
    signal SplitControl.startDone(error);
  }

  command error_t SplitControl.stop() {
    return call SerialControl.stop();
  }

  event void SerialControl.stopDone(error_t error) {
    signal SplitControl.stopDone(error);
  }

  command void SerialLogger.log(uint16_t evt, uint16_t data) {
    message_t* msg = call Pool.get();
    serial_log_message_t* smsg = (serial_log_message_t*) call SerialSend.getPayload(msg, sizeof(serial_log_message_t));
    smsg->timestamp = call Timer.getNow();
    smsg->nodeid = TOS_NODE_ID;
    smsg->evt = evt;
    smsg->data = data;
    call Queue.enqueue(msg);
  }

  event void Timer.fired() {
    if (!serialBusy && !call Queue.empty()) {
      message_t* msg = call Queue.dequeue();
      call SerialSend.send(AM_BROADCAST_ADDR, msg, sizeof(serial_log_message_t));
      call Pool.put(msg);
      serialBusy = TRUE;
    }
  }

  event void SerialSend.sendDone(message_t * msg, error_t error) {
    if (error == SUCCESS) {
      serialBusy = FALSE;
    }
  }

}
