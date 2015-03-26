set state closed
set telnetCommand [list]

# telnet: http://tools.ietf.org/html/rfc854


proc telnetCommandNameToCode {telnetCommandName} {
  string map {WILL 251 WON'T 252 DO 253 DON'T 254 IAC 255} $telnetCommandName
}


proc getDataIn {fid} {
  global telnetCommand

  set IAC 255
  if {[catch {read $fid} dataIn]} {
    set state closed
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
        handleTelnetCommand $fid
      }
    }
  }
}


proc handleTelnetCommand {fid} {
  global telnetCommand
#puts "handleTelnetCommand - command: $telnetCommand"
  set optionCodes {251 252 253 254}
  set telnetCommandLength [llength $telnetCommand]

  set WILL 251
  set WONT 252
  set DO 253
  set DONT 254
  set IAC 255

  set ECHO 1

  if {$telnetCommandLength > 1} {
    set byte2 [lindex $telnetCommand 1]
    if {$byte2 in $optionCodes} {
      if {$telnetCommandLength == 3} {
        puts "telnetCommandIn: $telnetCommand - byte2: $byte2"
        set option [lindex $telnetCommand 2]
        if {$byte2 == $WILL} {
           puts "WILL: $WILL"
           if {$option == $ECHO} {
             sendTelnetCommand $fid [list $IAC $DO $ECHO]
           } else {
             sendTelnetCommand $fid [list $IAC $DONT $option]
           }
         } elseif {$byte2 == $DO} {
           puts "do command in option: $option - sending wont"
           sendTelnetCommand $fid [list $IAC $WONT $option]
         }
        set telnetCommand [list]
      }
    } else {
      set telnetCommand [list]
    }
  }
}


proc sendTelnetCommand {fid telnetCommand} {
  global state
puts "sendTelnetCommand - command: $telnetCommand"

  set binaryData [binary format c3 $telnetCommand]
  if {[catch {puts -nonewline $fid $binaryData}]} {
    puts "sendTElnetCommand - closing"
    set state closed
  }
}


proc sendDataOut {fid} {
  global state

  if {[catch {read stdin} ch]} {
    puts "sendByte: read catch"
  }

  #puts "sendByte - sending: $ch"

  if {[catch {puts -nonewline $fid $ch}]} {
    set state closed
  }
}


proc connected {fid} {
  global state
  set DO 253
  set IAC 255
  set ECHO 1

  chan event $fid writable {}

  if {[dict exists [chan configure $fid] -peername]} {
    puts "connected to [dict get [chan configure $fid] -peername]"
    set state open
    sendTelnetCommand $fid [list $IAC $DO $ECHO]
  } else {
  }
}


proc monitorFileClosed {fid} {
  global state

  if {[eof $fid]} {
    set state closed
  } else {
    #puts "file still open"
    after 500 [list monitorFileClosed $fid]
  }
}


proc serviceConnection {} {
  global state

  while {$state ne "closed"} {
    vwait state
  }
}


proc connect {hostname port} {
  global state
  set state connecting

  set fid [socket -async $hostname $port]
  chan configure $fid -translation binary -blocking 0 -buffering none
  chan configure stdin -translation binary -blocking 0 -buffering none
  chan configure stdout -translation binary -blocking 0 -buffering none
  chan event $fid writable [list connected $fid]
  chan event $fid readable [list getDataIn $fid]
  chan event stdin readable [list sendDataOut $fid]
  monitorFileClosed $fid
}
