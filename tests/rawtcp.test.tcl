package require Tcl 8.6
package require tcltest
namespace import tcltest::*

# Add module dir to tm paths
set ThisScriptDir [file dirname [info script]]
set LibDir [file normalize [file join $ThisScriptDir .. lib]]

source [file join $ThisScriptDir "test_helpers.tcl"]
source [file join $ThisScriptDir "chatter.tcl"]
source [file join $LibDir "logger.tcl"]
source [file join $LibDir "rawtcp.tcl"]


test connect-1 {Outputs CONNECT message to local when connected} -setup {
  testHelpers::createFakeModem

  lassign [chatter::init] inRead outWrite
  set echoPort [testHelpers::rawEchoListen]
  set rawTcp [RawTcp new $inRead $outWrite 0 0]
  set chatScript {
    {expect "CONNECT 1200"}
  }
} -body {
  $rawTcp connect localhost $echoPort
  chatter::chat $chatScript
} -cleanup {
  $rawTcp close
  testHelpers::stopListening
  testHelpers::closeRemote
  testHelpers::destroyFakeModem
  chatter::close
} -result {no errors}


test connect-2 {Outputs NO CARRIER message to local when failed to connect} -setup {
  testHelpers::createFakeModem

  set unusedPort [testHelpers::findUnusedPort]
  lassign [chatter::init] inRead outWrite
  set rawTcp [RawTcp new $inRead $outWrite 0 0]
  set chatScript {
    {expect "NO CARRIER"}
  }
} -body {
  $rawTcp connect localhost $unusedPort
  chatter::chat $chatScript
} -cleanup {
  testHelpers::destroyFakeModem
  chatter::close
} -result {no errors}


test connect-3 {Check can send and receive data} -setup {
  testHelpers::createFakeModem

  lassign [chatter::init] inRead outWrite
  set echoPort [testHelpers::rawEchoListen]
  set rawTcp [RawTcp new $inRead $outWrite 0 0]
  set chatScript {
    {expect "CONNECT 1200"}
    {send "this was sent from local"}
    {expect "this was sent from local"}
    {send "so was this"}
    {expect "so was this"}
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
  testHelpers::destroyFakeModem
  chatter::close
} -result {no errors}


test connect-4 {Check detects when remote connection has dropped and send a NO CARRIER message} -setup {
  testHelpers::createFakeModem

  lassign [chatter::init] inRead outWrite
  set echoPort [testHelpers::rawEchoListen]
  set rawTcp [RawTcp new $inRead $outWrite 0 0]
  set chatScript {
    {expect "CONNECT 1200"}
    {expect "NO CARRIER"}
  }
} -body {
  $rawTcp connect localhost $echoPort
  after 100 ::testHelpers::closeRemote
  $rawTcp maintainConnection
  chatter::chat $chatScript
} -cleanup {
  $rawTcp close
  testHelpers::stopListening
  testHelpers::destroyFakeModem
  chatter::close
} -result {no errors}


test listen-1 {Outputs CONNECT message to local when connected} -setup {
  testHelpers::createFakeModem

  lassign [chatter::init] inRead outWrite
  set rawTcp [RawTcp new $inRead $outWrite 0 0]
  set chatScript {
    {expect "CONNECT 1200"}
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
  testHelpers::destroyFakeModem
  chatter::close
} -result {no errors}


test listen-2 {Outputs RING message to local when receives connection if requested} -setup {
  testHelpers::createFakeModem

  lassign [chatter::init] inRead outWrite
  set rawTcp [RawTcp new $inRead $outWrite 1 0]
  set chatScript {
    {expect "RING"}
    {expect "CONNECT 1200"}
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
  testHelpers::destroyFakeModem
  chatter::close
} -result {no errors}


cleanupTests
