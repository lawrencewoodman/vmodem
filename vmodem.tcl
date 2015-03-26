source "c.tcl"
set state closed

proc localEcho {state} {
  if {$state} {
    exec stty echo
  } else {
     exec stty -echo
   }
}

proc validCmd {cmdLine} {
  if {[regexp {(?i)^atd[tp]?.*$} $cmdLine]} {
    return 1
  } else {
    return 0
  }
}


localEcho off
while {1} {
  set line [gets stdin]
  puts $line

  if {[validCmd $line]} {
    if {$line eq "atd0"} {
      puts "OK"
      set hostname localhost
      set port 1234
      set hostname "sdf.lonestar.org"
      set port 23
      #set hostname "particlesbbs.dyndns.org"
      #set port 6400
      #set hostname "bbs.dmine.net"
      #set port 23
#      set hostname "particlesbbs.dyndns.org"
#      set port 6400
      connect $hostname $port
      serviceConnection
      # TODO: Work out when to close connection
    }
  }
}


localEcho on

