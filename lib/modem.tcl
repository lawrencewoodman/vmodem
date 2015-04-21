#
# Emulate the hayes modem command interface.
#
# Copyright (C) 2015 Lawrence Woodman <lwoodman@vlifesystems.com>
#
# Licensed under an MIT licence.  Please see LICENCE.md for details.
#

set LibDir [file dirname [info script]]
source [file join $LibDir rawtcp.tcl]
source [file join $LibDir telnet.tcl]


::oo::class create Modem {
  variable mode
  variable line
  variable speed
  variable config
  variable transports
  variable currentTransport
  variable escapeBuffer
  variable lastLocalInputTime
  variable localInChannel
  variable localOutChannel
  variable oldLocalInConfig
  variable oldLocalOutConfig
  variable oldLocalInReadableEventScript


  constructor {_config _localInChannel _localOutChannel} {
    set config $_config
    set localInChannel $_localInChannel
    set localOutChannel $_localOutChannel
    set mode "off"
    set line ""
    set speed 1200
    set transports {}
    set escapeBuffer ""
    set lastLocalInputTime 0

    set oldLocalInConfig [chan configure $localInChannel]
    set oldLocalOutConfig [chan configure $localOutChannel]
    set oldLocalInReadableEventScript [
      chan event $localInChannel readable
    ]

    set selfObject [self object]
    chan configure $localInChannel \
                   -translation binary \
                   -blocking 0 -buffering none
    chan configure $localOutChannel \
                   -translation binary \
                   -blocking 0 -buffering none
    chan event $localInChannel \
               readable \
               [list ${selfObject}::my ReceiveFromLocal]
    dict with config {
      set transports [
        dict create telnet [Telnet new $selfObject \
                                       $ring_on_connect $wait_for_ata] \
                    rawtcp [RawTcp new $selfObject \
                                       $ring_on_connect $wait_for_ata]
      ]
    }

    my listen
  }


  destructor {
    my StopListening
    chan configure $localInChannel {*}$oldLocalInConfig
    chan configure $localOutChannel {*}$oldLocalOutConfig
    chan event $localInChannel readable $oldLocalInReadableEventScript
  }


  method listen {} {
    dict with config {
      if {$auto_answer} {
        if {$incoming_type eq "telnet" || $incoming_type eq "rawtcp"} {
          set currentTransport [dict get $transports $incoming_type]
          $currentTransport listen $incoming_port
        }
      }
    }
  }


  method ring {} {
    my sendToLocal "RING\r\n"
  }


  method emulate {} {
    set selfObject [self object]

    set problem [
      catch {
        my changeMode "command"
        while {$mode ne "off"} {
          vwait ${selfObject}::mode
        }
      } result options
    ]

    if {$problem} {
      logger::log critical "result: $result\noptions: $options"
      # report the error with original details
      dict unset options -level
      return -options $options $result
    }

    # TODO: Trap signls so that can close neatly
    logger::close
  }


  method changeMode {newMode} {
    if {$mode ne $newMode} {
      logger::log info "Entering $newMode mode"
      set mode $newMode
    }
  }


  method sendToLocal {localOutData} {
    if {[catch {puts -nonewline $localOutChannel $localOutData}]} {
      logger::log error "Couldn't write to local"
    }
  }


  method connected {} {
    my changeMode "on-line"
    my sendToLocal "CONNECT $speed\r\n"
    set lastLocalInputTime [clock milliseconds]
  }


  method disconnected {} {
    if {$mode eq "on-line"} {
      my sendToLocal "NO CARRIER\r\n"
    }
    my changeMode "command"
    my listen
  }


  method processLocalIn {localInData} {
    set LF 0x0A
    set CR 0x0D

    set bytesFromLocal [split $localInData {}]

    my sendToLocal $localInData

    foreach ch $bytesFromLocal {
      binary scan $ch c signedByte
      set unsignedByte [expr {$signedByte & 0xff}]
      if {$unsignedByte == $LF || $unsignedByte == $CR} {
        my ProcessLine
      } else {
        append line $ch
      }
    }
  }



  ########################
  # Internal Commands
  ########################
  method StopListening {} {
    dict for {transportType transportInst} $transports {
      $transportInst stopListening
    }
  }


  method ProcessLine {} {
    set line [string trim $line]

    if {$line ne ""} {
      my sendToLocal "\r\n"

      logger::eval info {
        set bytes [split $line {}]
        set msg "Received line:\n[::logger::dumpBytes $bytes]"
      }
      switch -regexp $line {
        {(?i)^at\s*d[tp"]?.*$} { ;#"
          my sendToLocal "OK\r\n"
          my Dial $line
          my changeMode "command"
        }
        {(?i)^at\s*a} {
          my sendToLocal "OK\r\n"
          set incomingType [dict get $config incoming_type]
          set currentTransport [dict get $transports $incomingType]
          $currentTransport completeInbondConnection
          my changeMode "command"
        }

        {(?i)^at.*$} {
          # Acknowledge but ignore any other AT command
          my sendToLocal "OK\r\n"
        }
      }
    }

    set line ""
  }


  method GetPhoneNumberDetails {phoneNumber} {
    global phonebook

    if {[dict exists $phonebook $phoneNumber]} {
      set phoneNumberRecord [dict get $phonebook $phoneNumber]
      dict create \
        hostname [dict get $phoneNumberRecord hostname] \
        port [my DictGetWithDefault $phoneNumberRecord port 23] \
        speed [my DictGetWithDefault $phoneNumberRecord speed 1200] \
        type [my DictGetWithDefault $phoneNumberRecord type "telnet"]
    } else {
      return {}
    }
  }


  method DictGetWithDefault {dictionary key default} {
    if {[dict exists $dictionary $key]} {
      return [dict get $dictionary $key]
    }

    return $default
  }


  method Dial {atdLine} {
    global phonebook

    if {[regexp {(?i)^at\s*d".*:\d+$} $atdLine]} { ; #"
      set hostname [regsub {(?i)^(at\s*d")(.*):(\d+)$} $atdLine {\2}] ; #"
      set port [regsub {(?i)^(at\s*d")(.*):(\d+)$} $atdLine {\3}] ; #"
      set type "telnet"
      set logMsg "Emulating dialing by telnetting to $hostname:$port"
    } elseif {[regexp {(?i)^at\s*d".*$} $atdLine]} { ; #"
      set hostname [regsub {(?i)^(at\s*d")(.*)$} $atdLine {\2}] ; #"
      set port 23
      set type "telnet"
      set logMsg "Emulating dialing by telnetting to $hostname:$port"
    } else {
      set phoneNumber [regsub {(?i)^(at\s*d[tp]?)(.*)$} $atdLine {\2}]
      set details [my GetPhoneNumberDetails $phoneNumber]

      if {$details eq {}} {
        logger::log info \
                    "Couldn't find phone number $phoneNumber in phonebook"
        my sendToLocal "NO CARRIER\r\n"
        return
      }

      set hostname [dict get $details hostname]
      set port [dict get $details port]
      set speed [dict get $details speed]
      set type [dict get $details type]

      if {$type eq "telnet"} {
        set logMsg "Emulating dialing $phoneNumber by telnetting to $hostname:$port"
      } else {
        set logMsg "Emulating dialing $phoneNumber by making raw tcp connection to $hostname:$port"
      }
    }

    my StopListening

    logger::log info $logMsg
    set currentTransport [dict get $transports $type]
    $currentTransport connect $hostname $port
  }


  method ReceiveFromLocal {} {
    if {[catch {read $localInChannel} dataFromLocal]} {
      logger::log error "Couldn't read from local"
      return
    }

    if {$mode eq "on-line"} {
      lassign [my DetectEscapeCode $dataFromLocal] isEscapeCode dataToSend
      if {$isEscapeCode} {
        my changeMode "command"
        my sendToLocal "+++"
        my processLocalIn $dataToSend
      } elseif {$dataToSend ne ""} {
        set lastLocalInputTime [clock milliseconds]
        $currentTransport sendLocalToRemote $dataToSend
      }
    } else {
      my processLocalIn $dataFromLocal
    }
  }


  method DetectEscapeCode {dataFromLocal} {
    set escape_code_guard_duration 950
    set timeNow [clock milliseconds]
    set receivedEscapeCode 0

    if { $timeNow - $lastLocalInputTime > $escape_code_guard_duration } {
      set i 0
      foreach ch [split $dataFromLocal {}] {
        if {$ch eq "+"} {
          append escapeBuffer "+"
        } else {
          break
        }
        incr i
      }

      set dataLeft [string range $dataFromLocal $i end]

      if {[string length $escapeBuffer] >= 3} {
        set escapeBuffer ""
        set receivedEscapeCode 1
        logger::log info "Received escape code +++"
        my changeMode "command"
        set dataFromLocal $dataLeft
      } elseif {$dataLeft ne ""} {
        set dataFromLocal "${escapeBuffer}${dataLeft}"
      }
    }

    list $receivedEscapeCode $dataFromLocal
  }
}
