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
package require Tcl 8.6
package require Tclx
package require cmdline

try {
  package require pty
} on error {} {
  puts stderr "pty package couldn't be found, disabling pseudo TTY support"
}

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
  variable phonebook
}


proc vmodem::loadPhonebook {config {phonebookFilename {}}} {
  variable vmodemAppDirs
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
    serial_device {
     serial_device 1 "A serial device for local input/output"
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

  return $config
}


proc vmodem::handleParameters {config parameters} {
  set options {
    {log.arg "" {Log information to supplied filename}}
    {pb.arg "" {Phonebook filename}}
  }

  if {[info commands "::pty::open"] ne {}} {
    lappend options {p {Use a pseudo TTY for local input/output}}
  }

  if {[dict exists $config serial_device]} {
    lappend options {
      s {Use a serial device for local input/output (experimental)}
    }
  }

  set usage ": vmodem.tcl \[options]\noptions:"
  try {
    set params [::cmdline::getoptions parameters $options $usage]
  } on error {result options} {
    puts stderr $result
    exit 1
  }

  dict with params {
    if {[dict exists $params p] && $p && [dict exists $params s] && $s} {
      puts stderr "Error: -p and -s options are mutually exclusive"
      puts stderr [::cmdline::usage $options $usage]
      exit 1
    }
    if {$pb ne ""} {
      loadPhonebook $config $pb
    } else {
      loadPhonebook $config
    }
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
  variable phonebook

  signal trap * {::vmodem::finish}
  set config [loadConfiguration]
  set params [handleParameters $config $commandLineArgs]
  dict with params {
    if {$log ne ""} {
      logger::init $log
    }
  }

  if {[dict exists $params p] && $p} {
    lassign [pty::open] masterIO slavePTYName
    puts "Using pseudo TTY device: $slavePTYName"
    logger::log info "Using pseudo TTY device: $slavePTYName"
    set modem [Modem new $config $phonebook $masterIO $masterIO]
  } elseif {[dict exists $params s] && $s} {
    set serial_device [dict get $config serial_device]
    dict with serial_device {
      set serialIO [open $name r+]
      fconfigure $serialIO -mode $baud,$parity,$data_bits,$stop_bits \
                           -handshake $handshake
      puts "Using serial device: $name configured as: $baud,$data_bits,$parity,$stop_bits - handshaking: $handshake"
      logger::log info "Using serial device: $name configured as: $baud,$data_bits,$parity,$stop_bits - handshaking: $handshake"
      set modem [Modem new $config $phonebook $serialIO $serialIO]
    }
  } else {
    set modem [Modem new $config $phonebook stdin stdout]
  }
  $modem on
}

try {
  vmodem::main $argv
} on error {result options} {
  logger::log critical "result: $result, options: $options"
  # report the error with original details
  dict unset options -level
  return -options $options $result
}


vwait forever
