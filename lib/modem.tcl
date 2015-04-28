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
  variable phonebook
  variable transports
  variable currentTransport
  variable escapeBuffer
  variable lastLocalInputTime
  variable localInChannel
  variable localOutChannel
  variable oldLocalInConfig
  variable oldLocalOutConfig
  variable oldLocalInReadableEventScript


  constructor {_config _phonebook _localInChannel _localOutChannel} {
    set config $_config
    set phonebook $_phonebook
    set localInChannel $_localInChannel
    set localOutChannel $_localOutChannel
    set mode "off"
    set line ""
    set transports {}
    set currentTransport {}
    set escapeBuffer ""
    set lastLocalInputTime 0

    my ResetSpeed
  }


  method on {} {
    if {$mode eq "off"} {
      my changeMode "command"
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
          dict create \
            telnet [Telnet new $ring_on_connect \
                               $wait_for_ata \
                               [list ${selfObject}::my hasRemoteEvent]] \
            rawtcp [RawTcp new $ring_on_connect \
                               $wait_for_ata \
                               [list ${selfObject}::my hasRemoteEvent]] \
        ]
      }

      my listen
    }
  }


  method off {} {
    if {$mode ne "off"} {
      my CloseAllTransports
      my StopListening
      chan configure $localInChannel {*}$oldLocalInConfig
      chan configure $localOutChannel {*}$oldLocalOutConfig
      chan event $localInChannel readable $oldLocalInReadableEventScript
      my changeMode "off"
    }
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


  method hasRemoteEvent {} {
    if {$mode eq "off"} {return}

    while {[set localData [$currentTransport getDataForLocal]] ne {}} {
      my sendToLocal $localData
    }

    while {[set message [$currentTransport getMessage]] ne {}} {
      switch $message {
        connected {
          my changeMode "on-line"
          my sendToLocal "CONNECT $speed\r\n"
          set lastLocalInputTime [clock milliseconds]
        }
        connectionClosed {
          my sendToLocal "NO CARRIER\r\n"
          set currentTransport {}
          my changeMode "command"
          my listen
          my ResetSpeed
        }
        connectionFailed {
          my sendToLocal "NO CARRIER\r\n"
          set currentTransport {}
          my changeMode "command"
          my listen
          my ResetSpeed
        }
        ringing {
          my sendToLocal "RING\r\n"
        }
      }
    }
  }


  method sendToLocal {localOutData} {
    if {[catch {puts -nonewline $localOutChannel $localOutData}]} {
      logger::log error "Couldn't write to local"
    }
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


  method isOnline {} {
    expr {$mode eq "on-line"}
  }



  ########################
  # Internal Commands
  ########################
  method ResetSpeed {} {
    set speed [dict get $config incoming_speed]
  }


  method StopListening {} {
    dict for {transportType transportInst} $transports {
      $transportInst stopListening
    }
  }


  method CloseAllTransports {} {
    dict for {transportType transportInst} $transports {
      $transportInst close
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
        {(?i)^at\s*d(t|p).*$} {
          my sendToLocal "OK\r\n"
          set whoToDial [
            regsub {(?i)^(at\s*d)(t|p)(.*)$} $line {\3}
          ]
          my Dial $whoToDial
          my changeMode "command"
        }
        {(?i)^at\s*a} {
          my sendToLocal "OK\r\n"
          set incomingType [dict get $config incoming_type]
          set currentTransport [dict get $transports $incomingType]
          $currentTransport completeInbondConnection
          my changeMode "command"
        }

        {(?i)^at\s*h0?} {
          my sendToLocal "OK\r\n"
          if {$currentTransport ne {}} {
            $currentTransport close
          }
        }

        {(?i)^at\s*o1?} {
          my changeMode "on-line"
        }

        {(?i)^at.*$} {
          # Acknowledge but ignore any other AT command
          my sendToLocal "OK\r\n"
        }
      }
    }

    set line ""
  }


  method Dial {whoToDial} {
    set whoToDial [string trim $whoToDial]
    set phoneNumber $whoToDial
    set details [$phonebook lookupPhoneNumber $phoneNumber]

    if {$details ne {}} {
      set hostname [dict get $details hostname]
      set port [dict get $details port]
      set speed [dict get $details speed]
      set type [dict get $details type]
      set logMsg "Emulating dialing $phoneNumber "
    } elseif {[regexp {[[:alpha:].]} $whoToDial]} {

      if {[regexp {^.+:\d+$} $whoToDial]} {
        set hostname [regsub {^(.+):(\d+)$} $whoToDial {\1}]
        set port [regsub {^(.+):(\d+)$} $whoToDial {\2}]
      } else {
        set hostname $whoToDial
        set port [dict get $config outbound_defaults port]
      }

      set type [dict get $config outbound_defaults type]
      set speed [dict get $config outbound_defaults speed]
      set logMsg "Emulating dialing "
    } else {
      logger::log info \
                  "Couldn't find phone number $phoneNumber in phonebook"
      my sendToLocal "NO CARRIER\r\n"
      return
    }

    if {$type eq "telnet"} {
      append logMsg "by telnetting to $hostname:$port"
    } else {
      append logMsg "by making raw tcp connection to $hostname:$port"
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
