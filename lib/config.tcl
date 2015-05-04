#
# Handle the config file
#
# Copyright (C) 2015 Lawrence Woodman <lwoodman@vlifesystems.com>
#
# Licensed under an MIT licence.  Please see LICENCE.md for details.
#
package require configurator


namespace eval config {
  package require AppDirs
  package require configurator
  namespace import ::configurator::*

  variable vmodemAppDirs [AppDirs new "LorryWoodman" "vmodem"]
}


proc config::load {{filename {}}} {
  variable vmodemAppDirs

  if {$filename eq {}} {
    set filename [file join [$vmodemAppDirs configHome] "vmodem.conf"]
  }

  if {[catch {open $filename r} fid]} {
    return -code error "Couldn't open config file: $filename"
  } else {
    set configContents [read $fid]
    close $fid
    try {
      set config [ParseConfig $configContents]
    } on error {result options} {
      return -code error "Error in config file $filename: $result"
    }
  }

  return $config
}



##########################
# Internal commands
##########################

proc config::ParseConfig {configContents} {
  set rootKeys {
    inbound {
      inbound 1 "Settings for handling inbound connections"
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

  set inboundKeys {
    port {
      port 1 "The port to accept inbound connections on"
    }
    type {
      type 1 "The type of inbound connection: telnet|rawtcpip"
    }
    speed {
      speed 1 "The speed of inbound connections"
    }
    auto_answer {
      auto_answer 1 "Whether to answer inbound connections: 1|0"
    }
    ring_on_connect {
      ring_on_connect
      1
      "Whether to give RING message on inbound connection: 1|0"
    }
    wait_for_ata {
      wait_for_ata
      1
      "Whether to wait for ATA before completing inbound connection: 1|0"
    }
  }

  set outbound_defaultsKeys {
    port {
      port 1 "The default port to make outbound connections to"
    }
    type {
      type 1 "The default type of outbound connection: telnet|rawtcpip"
    }
    speed {
      speed 1 "The default speed for outbound connections"
    }
  }

  set serial_deviceKeys {
    name {
      name 1 "The name of the serial device"
    }
    speed {
      speed 1 "The speed of the serial device"
    }
    data_bits {
      data_bits 1 "The number of data bits in each character: 5|6|7|8"
    }
    parity {
      parity 1 "Parity method: n|o|e|m|s"
    }
    stop_bits {
      stop_bits 1 "The number of bits to use to indicate end of character: 1|2"
    }
    handshake {
      handshake 1 "The type of handshake control: none|rtscts|xonxoff"
    }
  }

  set config [configurator::parseConfig -keys $rootKeys $configContents]
  set inbound [dict get $config inbound]
  set outbound_defaults [dict get $config outbound_defaults]
  set serial_device [dict get $config serial_device]

  dict set config inbound [
    configurator::parseConfig -keys $inboundKeys $inbound
  ]
  dict set config outbound_defaults [
    configurator::parseConfig -keys $outbound_defaultsKeys $outbound_defaults
  ]
  dict set config serial_device [
    configurator::parseConfig -keys $serial_deviceKeys $serial_device
  ]

  lassign [IsConfigValid $config] isValidConfig notValidMsg
  if {!$isValidConfig} {
    return -code error "$notValidMsg"
  }

  return $config
}


proc config::IsConfigValid {config} {
  set specificValueFields {
    local_io {stdio pseudo serial}
  }

  lassign [HaveSpecificValues $specificValueFields $config] \
          isValid notValidMsg
  if {!$isValid} {return [list 0 $notValidMsg]}
  lassign [IsSerialDeviceValid $config] isValid notValidMsg
  if {!$isValid} {return [list 0 $notValidMsg]}
  lassign [IsInboundValid $config] isValid notValidMsg
  if {!$isValid} {return [list 0 $notValidMsg]}
  lassign [IsOutbound_defaultsValid $config] isValid notValidMsg
  if {!$isValid} {return [list 0 $notValidMsg]}

  return {1 {}}
}


proc config::IsInboundValid {config} {
  set inbound [dict get $config inbound]
  set specificValueFields {
    type {telnet rawtcpip}
    auto_answer {1 0}
    ring_on_connect {1 0}
    wait_for_ata {1 0}
  }
  set integerFields {port speed}

  lassign [HaveSpecificValues $specificValueFields $inbound] \
          isValid notValidMsg
  if {!$isValid} {
    return [list 0 "In inbound: $notValidMsg"]
  }

  lassign [AreIntegers $integerFields $inbound] isValid notValidMsg
  if {!$isValid} {
    return [list 0 "In inbound: $notValidMsg"]
  }

  return {1 {}}
}


proc config::IsOutbound_defaultsValid {config} {
  set specificValueFields {
    type {telnet rawtcpip}
  }
  set integerFields {port speed}
  set outbound_defaults [dict get $config outbound_defaults]

  lassign [HaveSpecificValues $specificValueFields $outbound_defaults] \
          isValid notValidMsg
  if {!$isValid} {
    return [list 0 "In outbound_defaults: $notValidMsg"]
  }

  lassign [AreIntegers $integerFields $outbound_defaults] isValid notValidMsg
  if {!$isValid} {
    return [list 0 "In outbound_defaults: $notValidMsg"]
  }

  return {1 {}}
}


proc config::IsSerialDeviceValid {config} {
  set serial_device [dict get $config serial_device]
  set specificValueFields {
    data_bits {5 6 7 8}
    parity {n o e m s}
    stop_bits {1 2}
    handshake {none rtscts xonxoff}
  }
  set integerFields {speed}

  lassign [HaveSpecificValues $specificValueFields $serial_device] \
          isValid notValidMsg
  if {!$isValid} {
    return [list 0 "In serial_device: $notValidMsg"]
  }

  lassign [AreIntegers $integerFields $serial_device] isValid notValidMsg
  if {!$isValid} {
    return [list 0 "In serial_device: $notValidMsg"]
  }

  return {1 {}}
}


proc config::HaveSpecificValues {valueFields aDict} {
  dict for {valueField validValues} $valueFields {
    set fieldValue [dict get $aDict $valueField]
    if {$fieldValue ni $validValues} {
      return [list 0 "$valueField must be: [join $validValues "|"]"]
    }
  }

  return {1 {}}
}


proc config::AreIntegers {fields aDict} {
  foreach field $fields {
    if {![string is integer [dict get $aDict $field]]} {
      return [list 0 "$field must be an integer"]
    }
  }

  return {1 {}}
}
