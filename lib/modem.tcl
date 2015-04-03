namespace eval modem {
  variable mode "off"
  variable line ""
  variable speed 1200
}


proc modem::emulateModem {} {
  variable mode

  set problem [
    catch {
      chan configure stdin -translation binary -blocking 0 -buffering none
      chan configure stdout -translation binary -blocking 0 -buffering none
      chan event stdin readable [list ::modem::ReceiveFromStdin]

      changeMode "command"
      while {$mode ne "off"} {
        vwait ::modem::mode
      }
    } result options
  ]

  if {$problem} {
    logger::log critical "result: $result\noptions: $options"
    # report the error with original details
    dict unset options -level
    return -options $options $result
  }

  # TODO: Trap signls so that can close neatly
  logger::close
}


proc modem::changeMode {newMode} {
  variable mode

  if {$mode ne $newMode} {
    logger::log info "Entering $newMode mode"
    set mode $newMode
  }
}


########################
# Internal Commands
########################
proc modem::ProcessLine {} {
  variable line

  set line [string trim $line]
  if {$line ne ""} {
    puts ""

    logger::eval info {
      set bytes [split $line {}]
      set msg "Received line:\n[::logger::dumpBytes $bytes]"
    }

    switch -regexp $line {
      {(?i)^atd[tp"]?.*$} { ;#"
        Dial $line
        ::modem::changeMode "command"
      }

      {(?i)^at.*$} {
        # Acknowledge but ignore any other AT command
        puts "OK"
      }
    }
  }

  set line ""
}


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


proc modem::ReceiveFromStdin {} {
  variable line

  set LF 0x0A
  set CR 0x0D

  if {[catch {read stdin} dataFromStdin]} {
    logger::log error "Couldn't read from stdin"
    return
  }

  set bytesFromStdin [split $dataFromStdin {}]

  foreach ch $bytesFromStdin {
    logger::eval info {
      set msg "Received bytes:\n[::logger::dumpBytes $bytesFromStdin]"
    }
    binary scan $ch c signedByte
    set unsignedByte [expr {$signedByte & 0xff}]
    if {$unsignedByte == $LF || $unsignedByte == $CR} {
      ProcessLine
    } else {
      append line $ch
    }

  }

  if {[catch {puts -nonewline $dataFromStdin}]} {
    logger::log error "Couldn't write to stdout"
    return
  }
}
