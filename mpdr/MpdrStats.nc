interface MpdrStats {

  command uint16_t getSentRadio1();

  command uint16_t getSentRadio2();

  command uint16_t getReceivedRadio1();

  command uint16_t getReceivedRadio2();

  command uint16_t getDropped();

  command uint32_t getTimeRadio1();

  command uint32_t getTimeRadio2();

  command uint16_t getRetransmissions();

  command uint16_t getMaxQueueSize1();

  command uint16_t getMaxQueueSize2();

  command void clear();

}
