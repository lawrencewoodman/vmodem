#
# Handle the config file
#
# Copyright (C) 2015 Lawrence Woodman <lwoodman@vlifesystems.com>
#
# Licensed under an MIT licence.  Please see LICENCE.md for details.
#
package require configurator
namespace import configurator::*


namespace eval config {
  package require AppDirs
  package require configurator
  namespace import ::configurator::*

  variable vmodemAppDirs [AppDirs new "LorryWoodman" "vmodem"]
}


proc config::load {} {
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
    local_io {
      local_io 1 "Type of local input/output: stdio|pseudo|serial"
    }
  }

  if {[catch {open $filename r} fid]} {
    return -code error "Couldn't open config file: $filename"
  } else {
    set configContents [read $fid]
    close $fid
    try {
      set config [parseConfig -keys $keys $configContents]
    } on error {result options} {
      return -code error "Error in config file $filename: $result"
    }
  }

  lassign [IsConfigValid $config] isValidConfig notValidMsg
  if {!$isValidConfig} {
    return -code error "Error in config file $filename: $notValidMsg"
  }

  return $config
}


##########################
# Internal commands
##########################

proc config::IsConfigValid {config} {
  set numberFields {incoming_port incoming_speed}
  foreach numberField $numberFields {
    if {![string is integer [dict get $config $numberField]]} {
      return [list 0 "$numberField must be a number"]
    }
  }

  set specificValueFields {
    auto_answer {0 1}
    ring_on_connect {0 1}
    wait_for_ata {0 1}
    incoming_type {telnet rawtcp}
    local_io {stdio pseudo serial}
  }

  dict for {specificValueField validValues} $specificValueFields {
    set fieldValue [dict get $config $specificValueField]
    if {$fieldValue ni $validValues} {
      return [list 0 "$specificValueField must be: [join $validValues "|"]"]
    }
  }

# TODO: validate outbound_defaults and serial_device

  return {1 {}}
}
