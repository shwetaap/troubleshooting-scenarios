#!/bin/bash

##########################################################
#
# Simple logging helpers for NetObserv install scripts.
#
##########################################################

errormsg() {
  echo -e "\U0001F6A8 ERROR: ${1}"
}

infomsg() {
  echo -e "\U0001F4C4 ${1}"
}

warnmsg() {
  echo -e "\U000026A0\uFE0F  WARN: ${1}"
}
