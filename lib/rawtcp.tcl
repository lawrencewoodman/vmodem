#
# Connect to a remote host using a raw tcp/ip connection
#
# Copyright (C) 2015 Lawrence Woodman <lwoodman@vlifesystems.com>
#
# Licensed under an MIT licence.  Please see LICENCE.md for details.
#
package require TclOO

::oo::class create RawTcp {
  variable state
  variable remoteChannel
  variable serverChannel
  variable ringOnConnect
  variable waitForAta
  variable modem

  constructor {modemInst _ringOnConnect _waitForAta} {
    set modem $modemInst
    set ringOnConnect $_ringOnConnect
    set waitForAta $_waitForAta

    set state closed
    set remoteChannel {}
    set serverChannel {}
  }


  method listen {port} {
    my ListenWithLogMsg $port "Listening for raw connection on port: $port"
  }


  method stopListening {} {
    if {$serverChannel ne {}} {
      logger::log info "Stop listening"
      close $serverChannel
      set serverChannel {}
    }
  }


  method completeInbondConnection {} {
    if {[catch {my connect}]} {
      set state closed
    }
  }


  method connect {args} {
    set usage ": connect hostname port\n  connect"
    set numArgs [llength $args]

    if {$numArgs == 2} {
      lassign $args hostname port
      try {
        set remoteChannel [socket $hostname $port]
      } on error {} {
        $modem sendToLocal "NO CARRIER\r\n"
        $modem disconnected
        return
      }
    } elseif {$numArgs != 0} {
      puts stderr $usage
      return -code error "Wrong number of arguments"
    }

    set state connecting
    my ConfigChannels
  }


  method isConnected {} {
    expr {$state eq "open"}
  }


  method close {} {
    if {$state ne "closed"} {
      close $remoteChannel
      $modem disconnected
      set state closed
    }
  }


  method sendLocalToRemote {localData} {
    lassign [my ProcessLocalDataBeforeSending $localData] \
            dataToSend \
            logMsg

    my SendData $dataToSend
    logger::log -noheader $logMsg
  }



  ############################
  # Private methods
  ############################

  method GetFromRemote {} {
    if {[catch {read $remoteChannel} dataIn] || $dataIn eq ""} {
      my close
      logger::log notice "Couldn't read from remote host, closing connection"
      return
    }

    set bytesIn [split $dataIn {}]
    logger::eval info {
      set numBytes [llength $bytesIn]
      if {$numBytes > 0} {
        set msg "remote > local: length $numBytes"
      }
    }

    logger::eval -noheader {
      ::logger::dumpBytes $bytesIn
    }

    return $dataIn
  }


  method ConfigChannels {} {
    set selfNamespace [self namespace]
    chan configure $remoteChannel -translation binary \
                                  -blocking 0 \
                                  -buffering none
    chan event $remoteChannel writable [list ${selfNamespace}::my Connected]
    chan event $remoteChannel readable [
      list ${selfNamespace}::my ReceiveFromRemote
    ]
  }


  method SendData {dataOut} {
    set bytesOut [split $dataOut {}]
    set numBytes [llength $bytesOut]
    if {$numBytes == 0} {
      return
    }


    logger::log info "local > remote: length $numBytes"
    logger::eval -noheader {::logger::dumpBytes $bytesOut}

    if {[catch {puts -nonewline $remoteChannel $dataOut}]} {
      my close
      logger::log notice "Couldn't write to remote host, closing connection"
      return
    }

  }


  method ProcessLocalDataBeforeSending {dataIn} {
    return [list $dataIn ""]
  }


  method ReceiveFromRemote {} {
    if {[$modem isOnline]} {
      $modem sendToLocal [my GetFromRemote]
    }
  }


  method Connected {} {
    chan event $remoteChannel writable {}

    if {[dict exists [chan configure $remoteChannel] -peername]} {
      set peername [dict get [chan configure $remoteChannel] -peername]
      logger::log info "Connected to $peername"
      $modem connected
      set state open
    }
  }


  method ServiceIncomingConnection {channel addr port} {
    my stopListening
    set remoteChannel $channel

    if {$ringOnConnect} {
      $modem ring
    }

    if {$waitForAta} {
      logger::log info "Recevied connection from: $addr, waiting for ATA"
    } else {
      logger::log info "Recevied connection from: $addr"
      my connect
    }
  }


  method ListenWithLogMsg {port logMsg} {
    if {$state ne "open"} {
      logger::log info $logMsg

      set selfNamespace [self namespace]
      set serverChannel [
        socket -server [list ${selfNamespace}::my ServiceIncomingConnection] \
                       $port
      ]
    }
  }

}
