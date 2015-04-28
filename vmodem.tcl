#! /usr/bin/env tclsh
# Virtual modem
#
# Copyright (C) 2015 Lawrence Woodman <lwoodman@vlifesystems.com>
#
# Licensed under an MIT licence.  Please see LICENCE.md for details.
#
# Emulate a modem so that applications such as vice can use it to connect to
# machines across the internet as if they were dialling a phone number on a
# modem.
#
package require Tcl 8.5
package require Tclx
package require cmdline
package require AppDirs
package require configurator
namespace import configurator::*

set ThisScriptDir [file dirname [info script]]
set LibDir [file join $ThisScriptDir lib]
source [file join $LibDir logger.tcl]
source [file join $LibDir phonebook.tcl]
source [file join $LibDir modem.tcl]


namespace eval vmodem {
  variable vmodemAppDirs [AppDirs new "LorryWoodman" "vmodem"]
  variable modem
  variable config
  variable phonebook
}


proc vmodem::loadPhonebook {{phonebookFilename {}}} {
  variable vmodemAppDirs
  variable config
  variable phonebook
  if {$phonebookFilename eq {}} {
    set phonebookFilename [file join [$vmodemAppDirs configHome] "phonebook"]
  }

  set phonebook [Phonebook new [dict get $config outbound_defaults]]
  $phonebook loadNumbersFromFile $phonebookFilename
  return $phonebook
}


proc vmodem::loadConfiguration {} {
  variable vmodemAppDirs
  variable config
  set filename [file join [$vmodemAppDirs configHome] "modem.conf"]

  set keys {
    incoming_port {
      incoming_port 1 "The port to accept incoming connections on"
    }
    incoming_type {
      incoming_type 1 "The type of incoming connection: telnet|rawtcp"
    }
    auto_answer {
      auto_answer 1 "Whether to answer incoming connections: 1|0"
    }
    ring_on_connect {
      ring_on_connect
      1
      "Whether to give RING message on incoming connection: 1|0"
    }
    wait_for_ata {
      wait_for_ata
      1
      "Whether to wait for ATA before completing incoming connection: 1|0"
    }
    incoming_speed {
      incoming_speed 1 "The default speed for incoming connections"
    }
    outbound_defaults {
      outbound_defaults
      1
      "The default settings for making an outbound connection"
    }
  }

  if {[catch {open $filename r} fid]} {
    logger::log warning "Couldn't open file $filename, using defaults"
    puts stderr "Couldn't open file $filename, using defaults"
    set config {
      incoming_port 6400
      incoming_type telnet
      incoming_speed 1200
      auto_answer 0
      ring_on_connect 1
      wait_for_ata 1
      outbound_defaults {
        port 23
        speed 1200
        type telnet
      }
    }
  } else {
    set configContents [read $fid]
    close $fid
    set config [parseConfig $configContents]
  }
}


proc vmodem::handleParameters {parameters} {
  set options {
    {log.arg "" {Log information to supplied filename}}
    {pb.arg "" {Phonebook filename}}
  }

  set usage ": vmodem.tcl \[options]\noptions:"
  set params [::cmdline::getoptions parameters $options $usage]

  set pb [dict get $params pb]
  if {$pb ne ""} {
    loadPhonebook $pb
  } else {
    loadPhonebook
  }

  return $params
}


proc vmodem::finish {} {
  variable modem
  $modem off
  logger::close
  exit
}


proc vmodem::main {commandLineArgs} {
  variable modem
  variable config
  variable phonebook

  signal trap * {::vmodem::finish}
  loadConfiguration
  set params [handleParameters $commandLineArgs]
  dict with params {
    if {$log ne ""} {
      logger::init $log
    }
  }

  set modem [Modem new $config $phonebook stdin stdout]
  $modem on
}


if {[catch {vmodem::main $argv} result options]} {
  logger::log critical "result: $result, options: $options"
  # report the error with original details
  dict unset options -level
  return -options $options $result
}


vwait forever
