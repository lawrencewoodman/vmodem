#
# Connect to a remote host using a telnet connection
#
# Copyright (C) 2015 Lawrence Woodman <lwoodman@vlifesystems.com>
#
# Licensed under an MIT licence.  Please see LICENCE.md for details.
#
# Telnet Protocol Specification: http://tools.ietf.org/html/rfc854
#
package require TclOO

::oo::class create Telnet {
  superclass RawTcpip
  variable telnetCommandIn telnetCommandsOut

  constructor {_ringOnConnect _waitForAta {_eventNotifyScript {}}} {
    next $_ringOnConnect $_waitForAta $_eventNotifyScript
    set telnetCommandIn [list]
    set telnetCommandsOut [list]
  }


  method listen {port} {
    my ListenWithLogMsg $port "Listening for telnet connection on port: $port"
  }


  ############################
  # Private methods
  ############################

  method ReceiveFromRemote {} {
    set IAC 255
    set dataIn [my GetFromRemote]
    set bytesIn [split $dataIn {}]

    foreach ch $bytesIn {
      binary scan $ch c signedByte
      set unsignedByte [expr {$signedByte & 0xff}]
      if {[llength $telnetCommandIn] == 0} {
        if {$unsignedByte == $IAC} {
          lappend telnetCommandIn $unsignedByte
        } else {
          my SendToLocal $ch
        }
      } else {
        lappend telnetCommandIn $unsignedByte
        my HandleTelnetCommand
      }
    }

    my SendTelnetCommands
  }


  method MakeTelnetCommandReadable {telnetCommand} {
    set telnetCommandLength [llength $telnetCommand]
    set codesMap {
        1 ECHO
       34 LINEMODE
      251 WILL
      252 WONT
      253 DO
      254 DONT
      255 IAC
    }

    set humanReadableCommand ""

    foreach b $telnetCommand {
      if {[dict exists $codesMap $b]} {
        set mneumonic [dict get $codesMap $b]
        append humanReadableCommand "$mneumonic "
      } else {
        append humanReadableCommand "$b "
      }
    }

    return $humanReadableCommand
  }


  method NegotiateTelnetOptions {command option} {
    set WILL 251
    set WONT 252
    set DO 253
    set DONT 254
    set IAC 255

    set ECHO 1

    switch $command  \
      $WILL {
        if {$option == $ECHO} {
          lappend telnetCommandsOut [list $IAC $DO $ECHO]
        } else {
          lappend telnetCommandsOut [list $IAC $DONT $option]
        }
      } \
      $WONT {
        if {$option == $ECHO} {
          lappend telnetCommandsOut [list $IAC $DO $ECHO]
        } else {
          lappend telnetCommandsOut [list $IAC $DONT $option]
        }
      } \
      $DO {
        lappend telnetCommandsOut [list $IAC $WONT $option]
      } \
      $DONT {
        lappend telnetCommandsOut [list $IAC $WONT $option]
      }
  }


  method HandleTelnetCommand {} {
    set commandCodes {251 252 253 254}
    set telnetCommandInLength [llength $telnetCommandIn]
    set humanReadableCommand [my MakeTelnetCommandReadable $telnetCommandIn]

    set IAC 255

    if {$telnetCommandInLength > 1} {
      set byte2 [lindex $telnetCommandIn 1]
      if {$byte2 == $IAC} {
        logger::log -noheader debug "    Telnet command: $humanReadableCommand"
        # IAC escapes IAC, so if you want to send or receive 255 then you need to
        # send IAC twice
        set binaryIAC [binary format c $IAC]
        my SendToLocal $binaryIAC
        set telnetCommandIn [list]
      } elseif {$byte2 in $commandCodes} {
        if {$telnetCommandInLength == 3} {
          logger::log -noheader \
                      debug \
                      "    Telnet command: $humanReadableCommand"
          set option [lindex $telnetCommandIn 2]
          my NegotiateTelnetOptions $byte2 $option
          set telnetCommandIn [list]
        }
      } else {
        set telnetCommandIn [list]
      }
    }
  }


  method SendTelnetCommands {} {
    set bytesToSend [list]
    set logMsg ""

    foreach telnetCommand $telnetCommandsOut {
      set binaryData [binary format c* $telnetCommand]

      set humanReadableCommand [my MakeTelnetCommandReadable $telnetCommand]
      lappend bytesToSend {*}[split $binaryData {}]
      append logMsg "    Telnet command: $humanReadableCommand\n"
    }

    my SendData [join $bytesToSend {}]

    if {$logMsg ne ""} {
      logger::log -noheader debug [string trimright $logMsg]
    }

    set telnetCommandsOut [list]
  }


  method EscapeIACs {dataIn} {
    set IAC 255
    set bytesOut [list]
    set bytesIn [split $dataIn {}]
    set numEscapedIAC 0

    foreach byte $bytesIn {
      binary scan $byte c signedByte
      set unsignedByte [expr {$signedByte & 0xff}]

      if {$unsignedByte == $IAC} {
        # Escape IAC by sending twice
        lappend bytesOut {*}[binary format c2 [list $IAC $IAC]]
        incr numEscapedIAC
      } else {
        lappend bytesOut $byte
      }
    }

    if {$numEscapedIAC > 0} {
      set logMsg "  Escaped IAC $numEscapedIAC time(s)"
    } else {
      set logMsg ""
    }

    list [join $bytesOut {}] $logMsg
  }


  method ProcessLocalDataBeforeSending {dataIn} {
    my EscapeIACs $dataIn
  }
}
