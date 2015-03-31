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
