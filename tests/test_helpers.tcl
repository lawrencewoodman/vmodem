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


proc testHelpers::rawEchoListen {} {
  variable listenChannel
  set port 1024

  while 1 {
    try {
      set listenChannel [
        socket -server ::testHelpers::ServiceIncomingConnection $port
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
proc testHelpers::ServiceIncomingConnection {channel addr port} {
  variable remoteChannel
  set remoteChannel $channel
  ::testHelpers::ConfigEchoConnection
}


proc testHelpers::ConfigEchoConnection {} {
  variable remoteChannel
  chan configure $remoteChannel -translation binary \
                                -blocking 0 \
                                -buffering none
  chan event $remoteChannel writable ::testHelpers::EchoConnected
  chan event $remoteChannel readable ::testHelpers::EchoInput
}


proc testHelpers::EchoConnected {} {
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
