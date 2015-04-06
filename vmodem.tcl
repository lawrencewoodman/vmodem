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
source [file join $LibDir rawtcp.tcl]
source [file join $LibDir telnet.tcl]


proc loadConfigFile {} {
  global phonebook

  set vmodemAppDirs [AppDirs new "LorryWoodman" "vmodem"]
  set phonebookFilename [file join [$vmodemAppDirs configHome] "phonebook"]
  loadPhonebook $phonebookFilename
}


proc loadPhonebook {filename} {
  global phonebook

  if {[catch {open $filename r} fid]} {
    puts stderr "Couldn't open file $filename, using defaults"
    set phonebook {}
  } else {
    set configContents [read $fid]
    close $fid
    set phonebook [parseConfig $configContents]
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


loadConfigFile
set params [handleParameters $argv]
dict with params {
  if {$log ne ""} {
    logger::init $log
  }
}

modem::emulateModem
