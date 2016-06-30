module MpdrForwardingEngineP {
  provides {
    interface Init;
    interface StdControl;
  }
  uses {

  }
}

implementation {

  command error_t Init.init() {

  }

  command error_t StdControl.start() {
    return SUCCESS;
  }

  command error_t StdControl.stop() {
    return SUCCESS;
  }

}
