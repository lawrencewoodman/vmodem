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
  variable messages
  variable remoteChannel
  variable serverChannel
  variable ringOnConnect
  variable waitForAta
  variable localOutBuffer
  variable eventNotifyScript

  constructor {_ringOnConnect _waitForAta {_eventNotifyScript {}}} {
    set ringOnConnect $_ringOnConnect
    set waitForAta $_waitForAta

    set state "closed"
    set messages [list]
    set remoteChannel {}
    set serverChannel {}
    set localOutBuffer [list]
    set eventNotifyScript $_eventNotifyScript
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


  method getDataForLocal {{numBytes 0}} {
    if {$numBytes > 0} {
      set lastIndex [expr {$numBytes - 1}]
      set ret [lrange $localOutBuffer 0 $lastIndex]
      set ret [join $ret {}]
      set localOutBuffer [lrange $localOutBuffer $numBytes end]
    } else {
      set ret [join $localOutBuffer {}]
      set localOutBuffer {}
    }
    return $ret
  }


  method getMessage {} {
    set message [lindex $messages 0]
    set messages [lrange $messages 1 end]
    return $message
  }


  method completeInbondConnection {} {
    if {[catch { my Report "connecting"
                 my ConfigChannels }    ]} {
      my Report "connectionFailed"
    }
  }


  method connect {hostname port} {
    my Report "connecting"

    if {[catch {set remoteChannel [socket $hostname $port]}]} {
      my Report "connectionFailed"
    } else {
      my ConfigChannels
    }
  }


  method close {} {
    if {$state ne "closed"} {
      my Report "connectionClosed"
      close $remoteChannel
      set remoteChannel {}
      set state "closed"
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

  method Report {message} {
    set validMessages {
      connecting
      connected
      connectionClosed
      connectionFailed
      ringing
    }

    if {$message ni $validMessages} {
      return -code error "$message is not a valid message"
    }

    lappend messages $message
    after idle $eventNotifyScript
  }


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


  method SendToLocal {dataToSend} {
    set moreLocalOutData 1
    lappend localOutBuffer $dataToSend
    after idle $eventNotifyScript
  }


  method ReceiveFromRemote {} {
    my SendToLocal [my GetFromRemote]
  }


  method Connected {} {
    set selfNamespace [self namespace]
    chan event $remoteChannel writable {}

    if {[dict exists [chan configure $remoteChannel] -peername]} {
      set peername [dict get [chan configure $remoteChannel] -peername]
      logger::log info "Connected to $peername"
      my Report "connected"
      set state "open"
      chan event $remoteChannel readable [
        list ${selfNamespace}::my ReceiveFromRemote
      ]
    }
  }


  method ServiceIncomingConnection {channel addr port} {
    my stopListening
    set remoteChannel $channel

    if {$ringOnConnect} {
      my Report "ringing"
    }

    if {$waitForAta} {
      logger::log info "Recevied connection from: $addr, waiting for ATA"
    } else {
      logger::log info "Recevied connection from: $addr"
      my completeInbondConnection
    }
  }


  method ListenWithLogMsg {port logMsg} {
    if {$state ne "open"} {
      logger::log info $logMsg
      set selfNamespace [self namespace]
      if {[catch {socket -server \
                         [list ${selfNamespace}::my ServiceIncomingConnection] \
                         $port} serverChannel]} {
        logger::log error "Couldn't create server on port: $port"
        return 0
      }
    }

    return 1
  }

}
