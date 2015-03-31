# Telnet Protocol Specification: http://tools.ietf.org/html/rfc854
namespace eval telnet {
  variable state closed
  variable oldStdinConfig
  variable oldStdoutConfig
  variable oldStdinReadableEventScript
  variable telnetCommand [list]
}


proc telnet::serviceConnection {} {
  variable state

  while {$state ne "closed"} {
    vwait ::telnet::state
  }
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
  variable telnetCommand

  set IAC 255
  if {[catch {read $fid} dataIn] || $dataIn eq ""} {
    Close $fid
    logger::log notice "Couldn't read from remote host, closing connection"
  } else {
    foreach ch [split $dataIn {}] {
      binary scan $ch c signedByte
      set unsignedByte [expr {$signedByte & 0xff}]
      if {[llength $telnetCommand] == 0} {
        if {$unsignedByte == $IAC} {
          lappend telnetCommand $unsignedByte
        } else {
          puts -nonewline $ch
        }
      } else {
        lappend telnetCommand $unsignedByte
        HandleTelnetCommand $fid
      }
    }
    logger::eval info {
      set msg "Received data: [DumpBytes $dataIn]"
    }
  }
}


proc telnet::DumpBytes {bytes} {
  set dump "$bytes ("

  foreach ch [split $bytes {}] {
    binary scan $ch c signedByte
    set unsignedByte [expr {$signedByte & 0xff}]
    lappend dump [format {%x} $unsignedByte]
  }

  return "$dump)"
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

  append humanReadableCommand "($telnetCommand)"
}


proc telnet::HandleTelnetCommand {fid} {
  variable telnetCommand
  set optionCodes {251 252 253 254}
  set telnetCommandLength [llength $telnetCommand]
  set humanReadableCommand [MakeTelnetCommandReadable $telnetCommand]

  set WILL 251
  set WONT 252
  set DO 253
  set DONT 254
  set IAC 255

  set ECHO 1

  if {$telnetCommandLength > 1} {
    set byte2 [lindex $telnetCommand 1]
    if {$byte2 == $IAC} {
      logger::log info "Received telnet command: $humanReadableCommand"
      # IAC escapes IAC, so if you want to send or receive 255 then you need to
      # send IAC twice
      if {[catch {puts -nonewline $fid $ch}]} {
        Close $fid
        logger::log notice "Couldn't write to remote host, closing connection"
      }
      set telnetCommand [list]
    } elseif {$byte2 in $optionCodes} {
      if {$telnetCommandLength == 3} {
        logger::log info "Received telnet command: $humanReadableCommand"
        set option [lindex $telnetCommand 2]
        if {$byte2 == $WILL} {
           if {$option == $ECHO} {
             SendTelnetCommand $fid [list $IAC $DO $ECHO]
           } else {
             SendTelnetCommand $fid [list $IAC $DONT $option]
           }
         } elseif {$byte2 == $DO || $byte2 == $DONT} {
           SendTelnetCommand $fid [list $IAC $WONT $option]
         }
        set telnetCommand [list]
      }
    } else {
      set telnetCommand [list]
    }
  }
}


proc telnet::SendTelnetCommand {fid telnetCommand} {
  variable state

  logger::eval info {
    set humanReadableCommand [MakeTelnetCommandReadable $telnetCommand]
    set msg "Sending telnet command:  $humanReadableCommand"
  }

  set binaryData [binary format c3 $telnetCommand]
  if {[catch {puts -nonewline $fid $binaryData}]} {
    Close $fid
    logger::log notice "Couldn't write to remote host, closing connection"
  }
}


proc telnet::SendToRemote {fid} {
  variable state
  set IAC 255
  set LF 0x0A
  set CR 0x0D

  if {[catch {read stdin} dataFromStdin]} {
    logger::log error "Couldn't read from stdin"
  }

  foreach dataOut [split $dataFromStdin {}] {
    binary scan $dataOut c signedByte
    set unsignedByte [expr {$signedByte & 0xff}]
    if {$unsignedByte == $IAC} {
      set dataOut [binary format c2 [list $IAC $IAC]]
    } elseif {0 && $unsignedByte == $LF} { # TODO: Add crlf switch
      set dataOut [binary format c2 [list $CR $LF]]
    }
    if {[catch {puts -nonewline $fid $dataOut}]} {
      Close $fid
      logger::log notice "Couldn't write to remote host, closing connection"
    }
  }
}


proc telnet::Connected {fid} {
  variable state
  set DO 253
  set IAC 255
  set ECHO 1

  chan event $fid writable {}

  if {[dict exists [chan configure $fid] -peername]} {
    set peername [dict get [chan configure $fid] -peername]
    logger::log info "Connected to $peername"
    set state open
  }
}
