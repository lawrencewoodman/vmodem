#
# Connect to a remote host using a raw tcp/ip connection
#
# Copyright (C) 2015 Lawrence Woodman <lwoodman@vlifesystems.com>
#
# Licensed under an MIT licence.  Please see LICENCE.md for details.
#
namespace eval rawtcp {
  variable state closed
  variable oldStdinConfig
  variable oldStdoutConfig
  variable oldStdinReadableEventScript
}


proc rawtcp::connect {args} {
  variable state
  variable oldStdinConfig
  variable oldStdoutConfig
  variable oldStdinReadableEventScript

  set options {
    {localReadableCmd.arg ::rawtcp::sendLocalToRemote
                          {Command prefix to call when local readable}}
    {remoteReadableCmd.arg ::rawtcp::ReceiveFromRemote
                           {Command prefix to call when remote readable}}
  }

  set usage ": connect \[options] hostname port\noptions:"
  set params [::cmdline::getoptions args $options $usage]

  if {[llength $args] != 2} {
    puts stderr "Error: Wrong number of arguments"
    ::cmdline::usage $options $usage
  }

  lassign $args hostname port
  set localReadableCmd [dict get $params localReadableCmd]
  set remoteReadableCmd [dict get $params remoteReadableCmd]

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
  chan event $fid writable [list ::rawtcp::Connected $fid]
  chan event $fid readable [list {*}$remoteReadableCmd $fid]
  chan event stdin readable [list {*}$localReadableCmd $fid]

  while {$state ne "closed"} {
    vwait ::rawtcp::state
  }
}


proc rawtcp::getFromRemote {fid} {
  if {[catch {read $fid} dataIn] || $dataIn eq ""} {
    Close $fid
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


proc rawtcp::sendLocalToRemote {args} {
  set options {
    {processCmd.arg "" {Command prefix to process local data before sending}}
  }

  set usage ": sendLocalToRemote \[options] fid\noptions:"
  set params [::cmdline::getoptions args $options $usage]

  if {[llength $args] != 1} {
    puts stderr "Error: Wrong number of arguments"
    ::cmdline::usage $options $usage
  }
  lassign $args fid
  set processCmd [dict get $params processCmd]

  if {[catch {read stdin} dataFromStdin]} {
    logger::log error "Couldn't read from stdin"
    return
  }

  if {$processCmd eq ""} {
    set dataToSend $dataFromStdin
    set logMsg ""
  } else {
    lassign [uplevel 1 [list {*}$processCmd $dataFromStdin]] dataToSend logMsg
  }

  sendData $fid $dataToSend
  logger::log -noheader $logMsg
}


proc rawtcp::sendData {fid dataOut} {
  set bytesOut [split $dataOut {}]
  set numBytes [llength $bytesOut]
  if {$numBytes == 0} {
    return
  }

  logger::log info "local > remote: length $numBytes"

  if {[catch {puts -nonewline $fid $dataOut}]} {
    Close $fid
    logger::log notice "Couldn't write to remote host, closing connection"
    return
  }

  logger::eval -noheader {::logger::dumpBytes $bytesOut}
}


############################
# Internal Commands
############################

proc rawtcp::Close {fid} {
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


proc rawtcp::ReceiveFromRemote {fid} {
  puts -nonewline [getFromRemote $fid]
}


proc rawtcp::Connected {fid} {
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
