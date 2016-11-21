interface MpdrStats {

  command uint16_t getSentRadio1();

  command uint16_t getSentRadio2();

  command uint16_t getReceivedRadio1();

  command uint16_t getReceivedRadio2();

  command uint16_t getDropped();

  command void clear();

}
