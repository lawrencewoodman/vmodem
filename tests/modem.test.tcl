package require Tcl 8.6
package require tcltest
namespace import tcltest::*

# Add module dir to tm paths
set ThisScriptDir [file dirname [info script]]
set LibDir [file normalize [file join $ThisScriptDir .. lib]]

source [file join $ThisScriptDir "test_helpers.tcl"]
source [file join $ThisScriptDir "chatter.tcl"]
source [file join $LibDir "logger.tcl"]
source [file join $LibDir "modem.tcl"]


test constructor-1 {Outputs OK message to local when an AT command is given} -setup {
  set config {ring_on_connect 0 wait_for_ata 0 auto_answer 0}
  lassign [chatter::init] inRead outWrite
  set modem [Modem new $config $inRead $outWrite]
  set chatScript {
    {send "ATZ\r\n"}
    {expect "ATZ\r\n"}
    {expect "OK\r\n"}
    {send "ath\r\n"}
    {expect "ath\r\n"}
    {expect "OK\r\n"}
  }
} -body {
  chatter::chat $chatScript
} -cleanup {
  chatter::close
} -result {no errors}


test constructor-2 {Recognize +++ and escape to command mode} -setup {
  set config {
    ring_on_connect 1
    wait_for_ata 0
    auto_answer 1
    incoming_type rawtcp
  }
  set port [testHelpers::findUnusedPort]
  dict set config incoming_port $port
  lassign [chatter::init] inRead outWrite
  set modem [Modem new $config $inRead $outWrite]
  set chatScript {
    {expect "RING\r\n"}
    {expect "CONNECT 1200\r\n"}
    {pause 1000}
    {send "+++"}
    {expect "+++"}
    {send "ath\r\n"}
    {expect "ath\r\n"}
    {expect "OK\r\n"}
  }
} -body {
  testHelpers::connect $port
  chatter::chat $chatScript
} -cleanup {
  testHelpers::closeRemote
  chatter::close
} -result {no errors}



cleanupTests
