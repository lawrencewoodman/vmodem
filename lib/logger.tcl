namespace eval logger {
  variable logFID
  variable active 0
}


proc logger::init {filename} {
  variable logFID
  variable active
  if {[catch {open $filename a} logFID]} {
    error "Couldn't open $filename for logging"
  }
  set active 1
}


proc logger::close {} {
  variable logFID
  variable active

  if {!$active} {return}
  ::close $logFID
}


proc logger::log {level msg} {
  variable logFID
  variable active

  if {!$active} {return}
  set currentTime [clock seconds]
  set formattedTime [clock format $currentTime -format {%Y-%m-%d %H:%M:%S}]
  set formattedMsg [format "%19s  %9s  %s" $formattedTime $level $msg]
  puts $logFID $formattedMsg
  flush $logFID
}


proc logger::eval {level script} {
  set result [uplevel 1 $script]
  log $level $result
}


proc logger::dumpBytes {bytes} {
  set byteNum 0

  foreach ch [split $bytes {}] {
    if {[string is print $ch]} {
      append dump $ch
    } else {
      append dump "."
    }
  }

  append dump " "

  foreach ch [split $bytes {}] {
    if {$byteNum == 0} {
      append dump "("
    } else {
      append dump " "
    }
    binary scan $ch c signedByte
    set unsignedByte [expr {$signedByte & 0xff}]
    append dump [format {%02x} $unsignedByte]
    incr byteNum
  }

  return "$dump)"
}
