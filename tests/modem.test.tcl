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


test on-1 {Outputs OK message to local when an AT command is given} -setup {
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
  $modem on
  chatter::chat $chatScript
} -cleanup {
  $modem off
  chatter::close
} -result {no errors}


test on-2 {Recognize +++ and escape to command mode} -setup {
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
    {expect "NO CARRIER\r\n"}
  }
} -body {
  $modem on
  testHelpers::connect $port
  chatter::chat $chatScript
} -cleanup {
  $modem off
  testHelpers::closeRemote
  chatter::close
} -result {no errors}


test on-3 {Ensure can resume a connect with ato from command mode} -setup {
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
    {send "atz\r\n"}
    {expect "atz\r\n"}
    {expect "OK\r\n"}
    {send "ato\r\n"}
    {expect "ato\r\n"}
    {send "atz"}
    {expect "atz"}
    {pause 1000}
    {send "+++ath0\r\n"}
    {expect "+++ath0\r\n"}
    {expect "OK\r\n"}
    {expect "NO CARRIER\r\n"}
  }
} -body {
  $modem on
  testHelpers::connect $port
  chatter::chat $chatScript
} -cleanup {
  $modem off
  testHelpers::closeRemote
  chatter::close
} -result {no errors}


test on-4 {Check will accept another inbound connectin once one finished} -setup {
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
    {send "how do you do\r\n"}
    {expect "how do you do\r\n"}
    {pause 1000}
    {send "+++"}
    {expect "+++"}
    {send "ath\r\n"}
    {expect "ath\r\n"}
    {expect "OK\r\n"}
    {expect "NO CARRIER\r\n"}
  }
} -body {
  $modem on
  testHelpers::connect $port
  chatter::chat $chatScript
  testHelpers::connect $port
  chatter::chat $chatScript
} -cleanup {
  $modem off
  testHelpers::closeRemote
  chatter::close
} -result {no errors}


test on-5 {Check will only accept one inbound connectin at a time} -setup {
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
    {send "how do you do\r\n"}
    {expect "how do you do\r\n"}
  }
} -body {
  $modem on
  testHelpers::connect $port
  chatter::chat $chatScript
  testHelpers::connect $port
} -cleanup {
  $modem off
  testHelpers::closeRemote
  chatter::close
} -result {0}


cleanupTests
