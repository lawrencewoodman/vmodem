#! /usr/bin/env tclsh
package require cmdline

set ThisScriptDir [file dirname [info script]]
set LibDir [file join $ThisScriptDir lib]
source [file join $LibDir logger.tcl]
source [file join $LibDir modem.tcl]
source [file join $LibDir telnet.tcl]

set phoneNumbers {
  0 {hostname localhost port 1234 speed 1200}
  1 {hostname sdf.lonestar.org port 23 speed 1200}
  2 {hostname particlesbbs.dyndns.org port 6400 speed 1200}
  3 {hostname bbs.dmine.net port 23 speed 1200}
}


proc handleParameters {parameters} {
  set options {
    {log.arg "" {Log information to supplied filename}}
  }

  set usage ": vmodem.tcl \[options]\noptions:"
  set params [::cmdline::getoptions parameters $options $usage]

  return $params
}


set params [handleParameters $argv]
dict with params {
  if {$log ne ""} {
    logger::init $log
  }
}

modem::emulateModem
