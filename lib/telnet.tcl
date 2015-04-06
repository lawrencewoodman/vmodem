# Telnet Protocol Specification: http://tools.ietf.org/html/rfc854
namespace eval telnet {
  variable state closed
  variable oldStdinConfig
  variable oldStdoutConfig
  variable oldStdinReadableEventScript
  variable telnetCommandIn [list]
  variable telnetCommandsOut [list]
}


proc telnet::connect {hostname port} {
  variable state
  variable oldStdinConfig
  variable oldStdoutConfig
  variable oldStdinReadableEventScript

  set state connecting
  set oldStdinConfig [chan configure stdin]
  set oldStdoutConfig [chan configure stdout]
  set oldStdinReadableEventScript [
    chan event stdin readable
  ]

  set fid [socket -async $hostname $port]
  chan configure $fid -translation binary -blocking 0 -buffering none
  chan configure stdin -translation binary -blocking 0 -buffering none
  chan configure stdout -translation binary -blocking 0 -buffering none
  chan event $fid writable [list ::telnet::Connected $fid]
  chan event $fid readable [list ::telnet::ReceiveFromRemote $fid]
  chan event stdin readable [list ::telnet::SendToRemote $fid]

  while {$state ne "closed"} {
    vwait ::telnet::state
  }
}


############################
# Internal Commands
############################

proc telnet::Close {fid} {
  variable state
  variable oldStdinConfig
  variable oldStdoutConfig
  variable oldStdinReadableEventScript

  if {$state ne "closed"} {
    close $fid
    chan configure stdin {*}$oldStdinConfig
    chan configure stdout {*}$oldStdoutConfig
    chan event stdin readable $oldStdinReadableEventScript
    set state closed
  }
}

proc telnet::ReceiveFromRemote {fid} {
  variable telnetCommandIn

  set IAC 255

  if {[catch {read $fid} dataIn] || $dataIn eq ""} {
    Close $fid
    logger::log notice "Couldn't read from remote host, closing connection"
  } else {
    set bytesIn [split $dataIn {}]

    logger::eval info {
      set numBytes [llength $bytesIn]
      if {$numBytes > 0} {
        set msg "remote > local: length $numBytes"
      }
    }

    foreach ch $bytesIn {
      binary scan $ch c signedByte
      set unsignedByte [expr {$signedByte & 0xff}]
      if {[llength $telnetCommandIn] == 0} {
        if {$unsignedByte == $IAC} {
          lappend telnetCommandIn $unsignedByte
        } else {
          puts -nonewline $ch
        }
      } else {
        lappend telnetCommandIn $unsignedByte
        HandleTelnetCommand $fid
      }
    }

    logger::eval -noheader {
      ::logger::dumpBytes $bytesIn
    }

    SendTelnetCommands $fid
  }
}


proc telnet::MakeTelnetCommandReadable {telnetCommand} {
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


proc telnet::NegotiateTelnetOptions {fid command option} {
  variable telnetCommandsOut
  set WILL 251
  set WONT 252
  set DO 253
  set DONT 254
  set IAC 255

  set ECHO 1

  if {$command == $WILL} {
    if {$option == $ECHO} {
      lappend telnetCommandsOut [list $IAC $DO $ECHO]
    } else {
      lappend telnetCommandsOut [list $IAC $DONT $option]
    }
  } elseif {$command == $DO || $byte2 == $DONT} {
    lappend telnetCommandsOut [list $IAC $WONT $option]
  }
}


proc telnet::HandleTelnetCommand {fid} {
  variable telnetCommandIn
  set commandCodes {251 252 253 254}
  set telnetCommandInLength [llength $telnetCommandIn]
  set humanReadableCommand [MakeTelnetCommandReadable $telnetCommandIn]

  set IAC 255

  if {$telnetCommandInLength > 1} {
    set byte2 [lindex $telnetCommandIn 1]
    if {$byte2 == $IAC} {
      logger::log -noheader "    Telnet command: $humanReadableCommand"
      # IAC escapes IAC, so if you want to send or receive 255 then you need to
      # send IAC twice
      set binaryIAC [binary format c $IAC]
      puts -nonewline $binaryIAC
      set telnetCommandIn [list]
    } elseif {$byte2 in $commandCodes} {
      if {$telnetCommandInLength == 3} {
        logger::log -noheader "    Telnet command: $humanReadableCommand"
        set option [lindex $telnetCommandIn 2]
        NegotiateTelnetOptions $fid $byte2 $option
        set telnetCommandIn [list]
      }
    } else {
      set telnetCommandIn [list]
    }
  }
}



proc telnet::SendTelnetCommands {fid} {
  variable telnetCommandsOut
  set dataSent [list]
  set numBytesToSend [llength [concat {*}$telnetCommandsOut]]

  if {$numBytesToSend == 0} {return}
  logger::log info "local > remote: length $numBytesToSend"

  foreach telnetCommand $telnetCommandsOut {
    set binaryData [binary format c* $telnetCommand]

    logger::eval -noheader {
      set humanReadableCommand [MakeTelnetCommandReadable $telnetCommand]
      set msg "    Telnet command: $humanReadableCommand"
    }

    if {[catch {puts -nonewline $fid $binaryData}]} {
      Close $fid
      logger::log notice "Couldn't write to remote host, closing connection"
    } else {
      lappend dataSent {*}[split $binaryData {}]
    }
  }

  logger::eval -noheader {
    ::logger::dumpBytes $dataSent
  }

  set telnetCommandsOut [list]
}


proc telnet::SendToRemote {fid} {
  variable telnetCommandsOut
  set IAC 255
  set LF 0x0A
  set CR 0x0D
  set dataSent [list]
  set numEscapedIAC 0

  if {[catch {read stdin} dataFromStdin]} {
    logger::log error "Couldn't read from stdin"
  }

  set bytesFromStdin [split $dataFromStdin {}]
  set numBytes [llength $bytesFromStdin]
  if {$numBytes == 0} {
    return
  }

  logger::log info "local > remote: length $numBytes"

  foreach dataOut $bytesFromStdin {
    binary scan $dataOut c signedByte
    set unsignedByte [expr {$signedByte & 0xff}]
    if {$unsignedByte == $IAC} {
      # Escape IAC by sending twice
      set dataOut [binary format c2 [list $IAC $IAC]]
      lappend dataSent {*}$dataOut
      incr numEscapedIAC
    } else {
      lappend dataSent $dataOut
      if {[catch {puts -nonewline $fid $dataOut}]} {
        Close $fid
        logger::log notice "Couldn't write to remote host, closing connection"
        return
      }
    }
  }

  logger::eval -noheader {
    set msg ""

    if {$numEscapedIAC} {
      append msg "  Escaped IAC $numEscapedIAC time(s)\n"
    }
    if {[llength $dataSent] > 0} {
      append msg [::logger::dumpBytes $dataSent]
    }

    set msg
  }
}


proc telnet::Connected {fid} {
  variable state

  chan event $fid writable {}

  if {[dict exists [chan configure $fid] -peername]} {
    set peername [dict get [chan configure $fid] -peername]
    logger::log info "Connected to $peername"
    ::modem::changeMode "on-line"
    puts "CONNECT $::modem::speed"
    set state open
  }
}
