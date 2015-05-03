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
source [file join $LibDir config.tcl]
source [file join $LibDir phonebook.tcl]
source [file join $LibDir modem.tcl]


namespace eval vmodem {
  variable vmodemAppDirs [AppDirs new "LorryWoodman" "vmodem"]
  variable modem
  variable phonebook
  variable localIn
  variable localOut
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


proc vmodem::handleParameters {parameters} {
  set options {
    {log.arg "" {Log information to supplied filename}}
    {pb.arg "" {Phonebook filename}}
    {c.arg "" {Config filename}}
  }

  set usage ": vmodem.tcl \[options]\noptions:"
  try {
    set params [::cmdline::getoptions parameters $options $usage]
  } on error {result options} {
    puts stderr $result
    exit 1
  }

  return $params
}


proc vmodem::finish {} {
  variable modem
  variable localIn
  variable localOut

  catch {
    $modem off
    logger::close
    close $localIn
    close $localOut
  }

  exit
}


proc vmodem::getLocalIO {config} {
  set local_io [dict get $config local_io]

  switch $local_io {
    stdio {
      return {stdin stdout}
    }

    pseudo {
      if {[info commands "::pty::open"] eq {}} {
        return -code error \
               "pty package not loaded, so local_io can't be pseudo in config"
      }
      lassign [pty::open] masterIO slavePTYName
      puts "Using pseudo TTY device: $slavePTYName"
      logger::log info "Using pseudo TTY device: $slavePTYName"
      return [list $masterIO $masterIO]
    }

    serial {
      if {![dict exists $config serial_device]} {
        return -code error \
               "serial_device not defined in config, so local_io can't be serial"
      }
      set serial_device [dict get $config serial_device]
      dict with serial_device {
        set serialIO [open $name r+]
        fconfigure $serialIO -mode $speed,$parity,$data_bits,$stop_bits \
                             -handshake $handshake
        puts "Using serial device: $name configured as: $speed,$data_bits,$parity,$stop_bits - handshaking: $handshake"
        logger::log info "Using serial device: $name configured as: $speed,$data_bits,$parity,$stop_bits - handshaking: $handshake"
        return [list $serialIO $serialIO]
      }
    }

    default {
      return -code error "invalid local_io setting: $local_io"
    }
  }
}


proc vmodem::main {commandLineArgs} {
  variable modem
  variable phonebook
  variable localIn
  variable localOut

  signal trap * {::vmodem::finish}

  set params [handleParameters $commandLineArgs]
  dict with params {
    if {$log ne ""} {
      logger::init $log
    }

    if {$c eq ""} {
      set config [config::load]
    } else {
      set config [config::load $c]
    }

    if {$pb ne ""} {
      loadPhonebook $config $pb
    } else {
      loadPhonebook $config
    }
  }

  lassign [getLocalIO $config] localIn localOut
  set modem [Modem new $config $phonebook $localIn $localOut]
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
