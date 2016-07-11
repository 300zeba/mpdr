#include "Mpdr.h"

configuration MpdrC {
  provides {
    interface StdControl;
    interface MpdrRouting;
    interface MpdrCommunication;
  }
}

implementation {
  components MpdrP;
  StdControl = MpdrP;
  MpdrRouting = MpdrP;
  MpdrCommunication = MpdrP;
}
