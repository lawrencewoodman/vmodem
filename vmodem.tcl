#! /usr/bin/env tclsh

set ThisScriptDir [file dirname [info script]]
set LibDir [file join $ThisScriptDir lib]
source [file join $LibDir telnet.tcl]

set phoneNumbers {
  0 {localhost 1234}
  1 {sdf.lonestar.org 23}
  2 {particlesbbs.dyndns.org 6400}
  3 {bbs.dmine.net 23}
}


proc dial {adtLine} {
  global phoneNumbers
  if {[regexp {(?i)^atd".*$} $adtLine]} { ; #"
    set hostname [regsub {(?i)^(atd")(.*),(\d+)$} $adtLine {\2}] ; #"
    set port [regsub {(?i)^(atd")(.*),(\d+)$} $adtLine {\3}] ; #"
  } else {
    set phoneNumber [regsub {(?i)^(atd[tp]?)(.*)$} $adtLine {\2}]
    if {[dict exists $phoneNumbers $phoneNumber]} {
      lassign [dict get $phoneNumbers $phoneNumber] hostname port
    } else {
      # TODO: Output no connect message
      return
    }
  }

  puts "OK"
  telnet::connect $hostname $port
  telnet::serviceConnection
  # TODO: Work out when to close connection
}


proc logMessage {error} {
  set fid [open "/tmp/vmodem.log" a]
  puts $fid $error
  close $fid
}

try {
  while {1} {
    set line [gets stdin]
    puts $line
    switch -regexp $line {
      {(?i)^atd[tp"]?.*$} { ;#"
        dial $line
      }
    }
  }
} on error {result options} {
  # TODO: This needs to be removed once all working
  logMessage "result: $result\noptions: $options"
}
