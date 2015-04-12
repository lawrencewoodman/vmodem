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
  variable oldStdinConfig oldStdoutConfig
  variable oldStdinReadableEventScript
  variable inBoundChannel
  variable serverChannel
  variable ringOnConnect
  variable waitForAta

  constructor {_ringOnConnect _waitForAta} {
    set ringOnConnect $_ringOnConnect
    set waitForAta $_waitForAta

    set state closed
    set inBoundChannel {}
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
    if {[catch {my connect $inBoundChannel}]} {
      puts "NO CARRIER"
    }
  }


  method connect {args} {
    set usage ": connect hostname port\n  connect incomingChannel"
    set numArgs [llength $args]

    set state connecting
    set oldStdinConfig [chan configure stdin]
    set oldStdoutConfig [chan configure stdout]
    set oldStdinReadableEventScript [
      chan event stdin readable
    ]
    set selfNamespace [self namespace]

    if {$numArgs == 1} {
      lassign $args fid
    } elseif {$numArgs == 2} {
      lassign $args hostname port
      set fid [socket -async $hostname $port]
    } else {
      puts stderr $usage
      return -code error "Wrong number of arguments"
    }

    chan configure $fid -translation binary -blocking 0 -buffering none
    chan configure stdin -translation binary -blocking 0 -buffering none
    chan configure stdout -translation binary -blocking 0 -buffering none
    chan event $fid writable [list ${selfNamespace}::my Connected $fid]
    chan event $fid readable [
      list ${selfNamespace}::my ReceiveFromRemote $fid
    ]
    chan event stdin readable [
      list ${selfNamespace}::my SendLocalToRemote $fid
    ]

    while {$state ne "closed"} {
      vwait ${selfNamespace}::state
    }
  }


  method getFromRemote {fid} {
    if {[catch {read $fid} dataIn] || $dataIn eq ""} {
      my Close $fid
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



  ############################
  # Private methods
  ############################

  method SendLocalToRemote {fid} {
    if {[catch {read stdin} dataFromStdin]} {
      return -code error "Couldn't read from stdin"
    }

    lassign [my ProcessLocalDataBeforeSending $dataFromStdin] \
            dataToSend \
            logMsg

    my sendData $fid $dataToSend
    logger::log -noheader $logMsg
  }


  method sendData {fid dataOut} {
    set bytesOut [split $dataOut {}]
    set numBytes [llength $bytesOut]
    if {$numBytes == 0} {
      return
    }

    logger::log info "local > remote: length $numBytes"

    if {[catch {puts -nonewline $fid $dataOut}]} {
      my Close $fid
      logger::log notice "Couldn't write to remote host, closing connection"
      return
    }

    logger::eval -noheader {::logger::dumpBytes $bytesOut}
  }


  method ProcessLocalDataBeforeSending {dataIn} {
    return [list $dataIn ""]
  }


  method Close {fid} {
    if {$state ne "closed"} {
      close $fid
      chan configure stdin {*}$oldStdinConfig
      chan configure stdout {*}$oldStdoutConfig
      chan event stdin readable $oldStdinReadableEventScript
      set state closed
      puts "NO CARRIER"
    }
  }


  method ReceiveFromRemote {fid} {
    puts -nonewline [my getFromRemote $fid]
  }


  method Connected {fid} {
    chan event $fid writable {}

    if {[dict exists [chan configure $fid] -peername]} {
      set peername [dict get [chan configure $fid] -peername]
      logger::log info "Connected to $peername"
      ::modem::changeMode "on-line"
      puts "CONNECT $::modem::speed"
      set state open
    }
  }


  method ServiceIncomingConnection {channel addr port} {
    my stopListening

    if {$ringOnConnect} {
      puts "RING"
    }

    if {$waitForAta} {
      logger::log info "Recevied connection from: $addr, waiting for ATA"
      set inBoundChannel $channel
    } else {
      logger::log info "Recevied connection from: $addr"
      my connect $channel
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
