package require Tcl 8.6
package require tcltest
namespace import tcltest::*

# Add module dir to tm paths
set ThisScriptDir [file dirname [info script]]
set LibDir [file normalize [file join $ThisScriptDir .. lib]]

source [file join $ThisScriptDir "test_helpers.tcl"]
source [file join $ThisScriptDir "chatter.tcl"]
source [file join $ThisScriptDir "fakemodem.tcl"]
source [file join $LibDir "logger.tcl"]
source [file join $LibDir "rawtcp.tcl"]


test connect-1 {Outputs CONNECT message to local when connected} -setup {
  lassign [chatter::init] inRead outWrite
  set modem [FakeModem new $inRead $outWrite]
  set echoPort [testHelpers::listen]
  set rawTcp [RawTcp new $modem 0 0]
  set chatScript {
    {expect "CONNECT 1200\r\n"}
  }
} -body {
  $rawTcp connect localhost $echoPort
  chatter::chat $chatScript
} -cleanup {
  $rawTcp close
  testHelpers::stopListening
  testHelpers::closeRemote
  chatter::close
} -result {no errors}


test connect-2 {Outputs NO CARRIER message to local when failed to connect} -setup {
  set unusedPort [testHelpers::findUnusedPort]
  lassign [chatter::init] inRead outWrite
  set modem [FakeModem new $inRead $outWrite]
  set rawTcp [RawTcp new $modem 0 0]
  set chatScript {
    {expect "NO CARRIER\r\n"}
  }
} -body {
  $rawTcp connect localhost $unusedPort
  chatter::chat $chatScript
} -cleanup {
  chatter::close
} -result {no errors}


test connect-3 {Check can send and receive data} -setup {
  lassign [chatter::init] inRead outWrite
  set modem [FakeModem new $inRead $outWrite]
  set echoPort [testHelpers::listen]
  set rawTcp [RawTcp new $modem 0 0]
  $modem setTransport $rawTcp
  set chatScript {
    {expect "CONNECT 1200\r\n"}
    {send "this was sent from local\r\n"}
    {expect "this was sent from local\r\n"}
    {send "so was this\r\n"}
    {expect "so was this\r\n"}
    {sendBinary {0x23 0xff 0x44}}
    {expectBinary {0x23 0xff 0x44}}
  }
} -body {
  $rawTcp connect localhost $echoPort
  chatter::chat $chatScript
} -cleanup {
  $rawTcp close
  testHelpers::stopListening
  testHelpers::closeRemote
  chatter::close
} -result {no errors}


test connect-4 {Check detects when remote connection has dropped and send a NO CARRIER message} -setup {
  lassign [chatter::init] inRead outWrite
  set modem [FakeModem new $inRead $outWrite]
  set echoPort [testHelpers::listen]
  set rawTcp [RawTcp new $modem 0 0]
  set chatScript {
    {expect "CONNECT 1200\r\n"}
    {expect "NO CARRIER\r\n"}
  }
} -body {
  $rawTcp connect localhost $echoPort
  after 100 ::testHelpers::closeRemote
  chatter::chat $chatScript
} -cleanup {
  $rawTcp close
  testHelpers::stopListening
  chatter::close
} -result {no errors}


test listen-1 {Outputs CONNECT message to local when connected} -setup {
  lassign [chatter::init] inRead outWrite
  set modem [FakeModem new $inRead $outWrite]
  set rawTcp [RawTcp new $modem 0 0]
  set chatScript {
    {expect "CONNECT 1200\r\n"}
  }
} -body {
  set foundPort 0
  set port 1024

  while {!$foundPort} {
    try {
      $rawTcp listen $port
      set foundPort 1
    } on error {} {
      incr port
    }
  }

  testHelpers::connect $port
  chatter::chat $chatScript
} -cleanup {
  $rawTcp close
  testHelpers::closeRemote
  chatter::close
} -result {no errors}


test listen-2 {Outputs RING message to local when receives connection if requested} -setup {
  lassign [chatter::init] inRead outWrite
  set modem [FakeModem new $inRead $outWrite]
  set rawTcp [RawTcp new $modem 1 0]
  set chatScript {
    {expect "RING\r\n"}
    {expect "CONNECT 1200\r\n"}
  }
} -body {
  set foundPort 0
  set port 1024

  while {!$foundPort} {
    try {
      $rawTcp listen $port
      set foundPort 1
    } on error {} {
      incr port
    }
  }

  testHelpers::connect $port
  chatter::chat $chatScript
} -cleanup {
  $rawTcp close
  testHelpers::closeRemote
  chatter::close
} -result {no errors}



cleanupTests
