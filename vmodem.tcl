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

package require cmdline
package require AppDirs
package require configurator
namespace import configurator::*

set ThisScriptDir [file dirname [info script]]
set LibDir [file join $ThisScriptDir lib]
source [file join $LibDir logger.tcl]
source [file join $LibDir modem.tcl]


proc loadConfiguration {} {
  global phonebook

  set vmodemAppDirs [AppDirs new "LorryWoodman" "vmodem"]
  set phonebookFilename [file join [$vmodemAppDirs configHome] "phonebook"]
  set configFilename [file join [$vmodemAppDirs configHome] "modem.conf"]
  loadPhonebook $phonebookFilename
  loadConfigFile $configFilename
}


proc loadPhonebook {filename} {
  global phonebook

  if {[catch {open $filename r} fid]} {
    logger::log warning "Couldn't open file $filename, not using phonebook"
    puts stderr "Couldn't open file $filename, not using phonebook"
    set phonebook {}
  } else {
    set phonebookContents [read $fid]
    close $fid
    set phonebook [parseConfig $phonebookContents]
  }
}


proc loadConfigFile {filename} {
  global config
  set keys {
    incoming_port {
      incoming_port 1 "The port to accept incoming connections on"
    }
    incoming_type {
      incoming_type telnet "The type of incoming connection: telnet|rawtcp"
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
  }

  if {[catch {open $filename r} fid]} {
    logger::log warning "Couldn't open file $filename, using defaults"
    puts stderr "Couldn't open file $filename, using defaults"
    set config {
      incoming_port 6400
      incoming_type telnet
      auto_answer 0
      ring_on_connect 1
      wait_for_ata 1
    }
  } else {
    set configContents [read $fid]
    close $fid
    set config [parseConfig $configContents]
  }
}


proc handleParameters {parameters} {
  set options {
    {log.arg "" {Log information to supplied filename}}
    {pb.arg "" {Phonebook filename}}
  }

  set usage ": vmodem.tcl \[options]\noptions:"
  set params [::cmdline::getoptions parameters $options $usage]

  set pb [dict get $params pb]
  if {$pb ne ""} {
    loadPhonebook $pb
  }

  return $params
}


loadConfiguration
set params [handleParameters $argv]
dict with params {
  if {$log ne ""} {
    logger::init $log
  }
}

set modem [Modem new $config stdin stdout]
$modem on
$modem emulate
