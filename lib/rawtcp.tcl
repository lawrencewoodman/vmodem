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
  variable oldLocalInConfig
  variable oldLocalOutConfig
  variable oldLocalInReadableEventScript
  variable remoteChannel
  variable serverChannel
  variable localInChannel
  variable localOutChannel
  variable ringOnConnect
  variable waitForAta

  constructor {_localInChannel _localOutChannel _ringOnConnect _waitForAta} {
    set localInChannel $_localInChannel
    set localOutChannel $_localOutChannel
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
      puts $localOutChannel "NO CARRIER"
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
      chan configure $localInChannel {*}$oldLocalInConfig
      chan configure $localOutChannel {*}$oldLocalOutConfig
      chan event $localInChannel readable $oldLocalInReadableEventScript
      set state closed
    }
  }


  method maintainConnection {} {
    set selfNamespace [self namespace]

    while {$state ne "closed"} {
      vwait ${selfNamespace}::state
    }

    puts $localOutChannel "NO CARRIER"
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
    set oldLocalInConfig [chan configure $localInChannel]
    set oldLocalOutConfig [chan configure $localOutChannel]
    set oldLocalInReadableEventScript [
      chan event $localInChannel readable
    ]

    chan configure $remoteChannel -translation binary \
                                  -blocking 0 \
                                  -buffering none
    chan configure $localInChannel -translation binary \
                                   -blocking 0 \
                                   -buffering none
    chan configure $localOutChannel -translation binary \
                                    -blocking 0 \
                                    -buffering none
    chan event $remoteChannel writable [list ${selfNamespace}::my Connected]
    chan event $remoteChannel readable [
      list ${selfNamespace}::my ReceiveFromRemote
    ]
    chan event $localInChannel readable [
      list ${selfNamespace}::my SendLocalToRemote
    ]
  }


  method SendLocalToRemote {} {
    if {[catch {read $localInChannel} dataFromStdin]} {
      return -code error "Couldn't read from local: $localInChannel"
    }

    lassign [my ProcessLocalDataBeforeSending $dataFromStdin] \
            dataToSend \
            logMsg

    my sendData $dataToSend
    logger::log -noheader $logMsg
  }


  method sendData {dataOut} {
    set bytesOut [split $dataOut {}]
    set numBytes [llength $bytesOut]
    if {$numBytes == 0} {
      return
    }

    logger::log info "local > remote: length $numBytes"

    if {[catch {puts -nonewline $remoteChannel $dataOut}]} {
      my close
      logger::log notice "Couldn't write to remote host, closing connection"
      return
    }

    logger::eval -noheader {::logger::dumpBytes $bytesOut}
  }


  method ProcessLocalDataBeforeSending {dataIn} {
    return [list $dataIn ""]
  }




  method ReceiveFromRemote {} {
    puts -nonewline $localOutChannel [my GetFromRemote]
  }


  method Connected {} {
    chan event $remoteChannel writable {}

    if {[dict exists [chan configure $remoteChannel] -peername]} {
      set peername [dict get [chan configure $remoteChannel] -peername]
      logger::log info "Connected to $peername"
      ::modem::changeMode "on-line"
      puts $localOutChannel "CONNECT $::modem::speed"
      set state open
    }
  }


  method ServiceIncomingConnection {channel addr port} {
    my stopListening

    if {$ringOnConnect} {
      puts $localOutChannel "RING"
    }

    set remoteChannel $channel
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
