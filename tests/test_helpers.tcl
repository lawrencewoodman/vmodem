# Helper functions for the tests

namespace eval testHelpers {
  variable listenChannel
  variable remoteChannel
}

proc testHelpers::createFakeModem {} {
  namespace eval ::modem {
    variable speed 1200

    proc changeMode {newMode} {
    }
  }
}


proc testHelpers::destroyFakeModem {} {
  namespace delete ::modem
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


proc testHelpers::rawEchoListen {{mode echo}} {
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


proc testHelpers::stopListening {} {
  variable listenChannel
  close $listenChannel
}


proc testHelpers::rawEchoConnect {port} {
  variable remoteChannel
  set remoteChannelhannel [socket -async $hostname $port]
  ConfigEchoConnection
}


proc testHelpers::sendData {dataOut} {
  variable remoteChannel
  puts -nonewline $remoteChannel $dataOut
}


proc testHelpers::closeRemote {} {
  variable remoteChannel
  close $remoteChannel
}



#############################
# Internal Commands
#############################
proc testHelpers::ServiceIncomingConnection {mode channel addr port} {
  variable remoteChannel
  set remoteChannel $channel

  if {$mode eq "echo"} {
    ::testHelpers::ConfigEchoConnection
  } else {
    ::testHelpers::ConfigDecrConnection
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


proc testHelpers::Connected {} {
  variable remoteChannel
  chan event $remoteChannel writable {}
}


proc testHelpers::EchoInput {} {
  variable remoteChannel
  if {[catch {read $remoteChannel} dataIn options] || $dataIn eq ""} {
    closeRemote
    return
  }

  puts -nonewline $remoteChannel "ECHO: $dataIn"
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
