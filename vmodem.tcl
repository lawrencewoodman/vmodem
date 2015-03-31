#! /usr/bin/env tclsh
package require log
package require cmdline

set ThisScriptDir [file dirname [info script]]
set LibDir [file join $ThisScriptDir lib]
source [file join $LibDir logger.tcl]
source [file join $LibDir telnet.tcl]

set phoneNumbers {
  0 {localhost 1234}
  1 {sdf.lonestar.org 23}
  2 {particlesbbs.dyndns.org 6400}
  3 {bbs.dmine.net 23}
}


proc dial {adtLine} {
  global phoneNumbers

  if {[regexp {(?i)^atd".*$} $adtLine]} { ; #"
    set hostname [regsub {(?i)^(atd")(.*),(\d+)$} $adtLine {\2}] ; #"
    set port [regsub {(?i)^(atd")(.*),(\d+)$} $adtLine {\3}] ; #"
    logger::log info "Emulating dialing by telnetting to $hostname:$port"
  } else {
    set phoneNumber [regsub {(?i)^(atd[tp]?)(.*)$} $adtLine {\2}]
    if {[dict exists $phoneNumbers $phoneNumber]} {
      lassign [dict get $phoneNumbers $phoneNumber] hostname port
      logger::log info \
          "Emulating dialing $phoneNumber by telnetting to $hostname:$port"
    } else {
      logger::log info \
                  "Couldn't find phone number $phoneNumber in phonebook"
      # TODO: Output no connect message
      return
    }
  }

  puts "OK"
  telnet::connect $hostname $port
  telnet::serviceConnection
  # TODO: Work out when to close connection
}


proc handleParameters {parameters} {
  set options {
    {log.arg "" {Log information to supplied filename}}
  }

  set usage ": vmodem.tcl \[options]\noptions:"
  set params [::cmdline::getoptions parameters $options $usage]

  return $params
}


proc emulateModem {} {
  set problem [
    catch {
      while {1} {
        logger::log info "Waiting for modem command"
        set line [gets stdin]
        puts $line
        switch -regexp $line {
          {(?i)^atd[tp"]?.*$} { ;#"
            dial $line
          }
        }
      }
    } result options
  ]

  if {$problem} {
    logger::log critical "result: $result\noptions: $options"
  }

  # TODO: Trap signls so that can close neatly
  logger::close
}


set params [handleParameters $argv]
dict with params {
  if {$log ne ""} {
    logger::init $log
  }
}

emulateModem
