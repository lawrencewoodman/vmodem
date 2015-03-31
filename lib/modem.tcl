namespace eval modem {
  variable speed 1200
}


proc modem::emulateModem {} {
  set problem [
    catch {
      while {1} {
        logger::log info "Waiting for modem command"
        set line [gets stdin]
        puts $line
        switch -regexp $line {
          {(?i)^atd[tp"]?.*$} { ;#"
            Dial $line
          }
        }
      }
    } result options
  ]

  if {$problem} {
    logger::log critical "result: $result\noptions: $options"
  }

  # TODO: Trap signls so that can close neatly
  logger::close
}


########################
# Internal Commands
########################
proc modem::Dial {adtLine} {
  variable speed
  global phoneNumbers

  if {[regexp {(?i)^atd".*$} $adtLine]} { ; #"
    set hostname [regsub {(?i)^(atd")(.*),(\d+)$} $adtLine {\2}] ; #"
    set port [regsub {(?i)^(atd")(.*),(\d+)$} $adtLine {\3}] ; #"
    logger::log info "Emulating dialing by telnetting to $hostname:$port"
  } else {
    set phoneNumber [regsub {(?i)^(atd[tp]?)(.*)$} $adtLine {\2}]
    if {[dict exists $phoneNumbers $phoneNumber]} {
      set phoneNumberRecord [dict get $phoneNumbers $phoneNumber]
      set hostname [dict get $phoneNumberRecord hostname]
      set port [dict get $phoneNumberRecord port]
      set speed [dict get $phoneNumberRecord speed]
      logger::log info \
          "Emulating dialing $phoneNumber by telnetting to $hostname:$port"
    } else {
      logger::log info \
                  "Couldn't find phone number $phoneNumber in phonebook"
      puts "NO CARRIER"
      return
    }
  }

  puts "OK"
  telnet::connect $hostname $port
  puts "NO CARRIER"
}
