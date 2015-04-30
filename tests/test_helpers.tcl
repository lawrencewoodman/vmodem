# Helper functions for the tests

namespace eval testHelpers {
  variable listenChannel
  variable remoteChannel
}


proc testHelpers::findUnusedPort {} {
  set port 1024

  while 1 {
    try {
      set channel [socket localhost $port]
      close $channel
      incr port
    } trap {POSIX ECONNREFUSED} {} {
      return $port
    }
  }
}


proc testHelpers::listen {{mode echo}} {
  variable listenChannel
  set port 1024

  while 1 {
    try {
      set listenChannel [
        socket -server [list ::testHelpers::ServiceIncomingConnection $mode] \
                       $port
      ]
      return $port
    } on error {} {
      incr port
    }
  }
}

proc testHelpers::connect {port} {
  variable remoteChannel
  try {
    set remoteChannel [socket localhost $port]
    ConfigEchoConnection
    return 1
  } on error {} {
    return 0
  }
}


proc testHelpers::stopListening {} {
  variable listenChannel
  close $listenChannel
}


proc testHelpers::sendData {dataOut} {
  variable remoteChannel
  puts -nonewline $remoteChannel $dataOut
}


proc testHelpers::closeRemote {} {
  variable remoteChannel
  catch {close $remoteChannel}
}


proc testHelpers::readLogToList {filename} {
  set fd [open $filename r]
  set logContents [read $fd]
  close $fd

  lmap entry [split $logContents "\n"] {
    set withoutDate [
      regsub {^(\d\d\d\d-\d\d-\d\d \d\d:\d\d:\d\d\s+)(.*)$} $entry {\2}
    ]
    set level [regsub {^([^ ]+)\s+(.*)$} $withoutDate {\1}]
    set msg [regsub {^([^ ]+)\s+(.*)$} $withoutDate {\2}]
    if {$msg eq ""} {continue}
    list $level $msg
  }
}



#############################
# Internal Commands
#############################
proc testHelpers::ServiceIncomingConnection {mode channel addr port} {
  variable remoteChannel
  set remoteChannel $channel

  switch $mode {
    echo {::testHelpers::ConfigEchoConnection}
    decr {::testHelpers::ConfigDecrConnection}
    telnet {::testHelpers::ConfigTelnetConnection}
  }
}


proc testHelpers::ConfigEchoConnection {} {
  variable remoteChannel
  chan configure $remoteChannel -translation binary \
                                -blocking 0 \
                                -buffering none
  chan event $remoteChannel writable ::testHelpers::Connected
  chan event $remoteChannel readable ::testHelpers::EchoInput
}


proc testHelpers::ConfigDecrConnection {} {
  variable remoteChannel
  chan configure $remoteChannel -translation binary \
                                -blocking 0 \
                                -buffering none
  chan event $remoteChannel writable ::testHelpers::Connected
  chan event $remoteChannel readable ::testHelpers::DecrInput
}


proc testHelpers::ConfigTelnetConnection {} {
  variable remoteChannel
  chan configure $remoteChannel -translation binary \
                                -blocking 0 \
                                -buffering none
  chan event $remoteChannel writable {::testHelpers::Connected 1}
  chan event $remoteChannel readable ::testHelpers::EchoEscapedTelnetInput
}


proc testHelpers::Connected {{doTelnetNegotation 0}} {
  variable remoteChannel
  chan event $remoteChannel writable {}

  if {$doTelnetNegotation} {
    NegotiateTelnetOptions
  }
}


proc testHelpers::NegotiateTelnetOptions {} {
  variable remoteChannel

  set telnetCodesMap {
    {WILL } {0xfb }
    {WONT } {0xfc }
    {DO } {0xfd }
    {DONT } {0xfe }
    {IAC } {0xff }
    {ECHO} 0x01
    {SUPRESS_GO_AHEAD} 0x03
    {LINEMODE} 0x34
  }
  set commands {
    {IAC WILL ECHO}
    {IAC WONT ECHO}
    {IAC WILL SUPRESS_GO_AHEAD}
    {IAC DO LINEMODE}
  }
  set commandsBytes [string map $telnetCodesMap $commands]

  foreach command $commandsBytes {
    set dataOut [binary format c* $command]
    puts -nonewline $remoteChannel $dataOut
  }
}


proc testHelpers::EchoInput {} {
  variable remoteChannel
  if {[catch {read $remoteChannel} dataIn options] || $dataIn eq ""} {
    closeRemote
    return
  }

  puts -nonewline $remoteChannel "$dataIn"
}


proc testHelpers::DecrInput {} {
  variable remoteChannel
  if {[catch {read $remoteChannel} dataIn options] || $dataIn eq ""} {
    closeRemote
    return
  }

  set bytes [split $dataIn {}]
  set dataOut [
    binary format c* [
      lmap byte $bytes {
        binary scan $byte c signedByte
        set unsignedByte [expr {$signedByte & 0xff}]
        expr {$unsignedByte - 1}
      }
    ]
  ]

  puts -nonewline $remoteChannel $dataOut
}


proc testHelpers::EchoEscapedTelnetInput {} {
  variable remoteChannel

  if {[catch {read $remoteChannel} dataIn options] || $dataIn eq ""} {
    closeRemote
    return
  }

  set IAC 0xff

  set bytes [split $dataIn {}]
  set bytesOut [list]

  foreach byte $bytes {
    binary scan $byte c signedByte
    set unsignedByte [expr {$signedByte & 0xff}]

    if {$unsignedByte == $IAC} {
      lappend bytesOut $IAC
    }
    lappend bytesOut $unsignedByte
  }

  set dataOut [binary format c* $bytesOut]
  puts -nonewline $remoteChannel $dataOut
}
