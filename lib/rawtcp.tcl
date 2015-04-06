namespace eval rawtcp {
  variable state closed
  variable oldStdinConfig
  variable oldStdoutConfig
  variable oldStdinReadableEventScript
}


proc rawtcp::connect {hostname port} {
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
  chan event $fid writable [list ::rawtcp::Connected $fid]
  chan event $fid readable [list ::rawtcp::ReceiveFromRemote $fid]
  chan event stdin readable [list ::rawtcp::SendToRemote $fid]

  while {$state ne "closed"} {
    vwait ::rawtcp::state
  }
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
  if {[catch {read $fid} dataIn] || $dataIn eq ""} {
    Close $fid
    logger::log notice "Couldn't read from remote host, closing connection"
    return
  }

  set bytesIn [split $dataIn {}]
  set numBytes [llength $bytesIn]
  if {$numBytes == 0} {
    return
  }

  logger::log info "remote > local: length $numBytes"

  puts -nonewline $dataIn

  logger::eval -noheader {
    ::logger::dumpBytes $bytesIn
  }
}


proc rawtcp::SendToRemote {fid} {
  set dataSent [list]

  if {[catch {read stdin} dataFromStdin]} {
    logger::log error "Couldn't read from stdin"
    return
  }

  set bytesFromStdin [split $dataFromStdin {}]
  set numBytes [llength $bytesFromStdin]
  if {$numBytes == 0} {
    return
  }

  logger::log info "local > remote: length $numBytes"

  if {[catch {puts -nonewline $fid $dataFromStdin}]} {
    Close $fid
    logger::log notice "Couldn't write to remote host, closing connection"
    return
  }
  logger::eval -noheader {
    ::logger::dumpBytes $bytesFromStdin
  }
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

