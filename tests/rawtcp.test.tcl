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
  set closeScript {
    $rawTcp close
    $rawTcp setPulseDelay 0
    testHelpers::stopListening
  }
  $rawTcp setPulseDelay 10
  $rawTcp setPulseScript [list chatter::chat $chatScript $closeScript $rawTcp]
} -body {
  $rawTcp connect localhost $echoPort
  chatter::getMsg
} -cleanup {
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
  set closeScript {
  }
} -body {
  $rawTcp connect localhost $unusedPort
  chatter::wait
  chatter::chat $chatScript $closeScript $rawTcp
  chatter::getMsg
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
    {expect "ECHO: this was sent from local"}
    {send "so was this"}
    {expect "ECHO: so was this"}
    {sendBinary {0x23 0xff 0x44}}
    {expectBinary {0x45 0x43 0x48 0x4f 0x3a 0x20 0x23 0xff 0x44}}
  }
  set closeScript {
    $rawTcp close
    $rawTcp setPulseDelay 0
    testHelpers::stopListening
  }
  $rawTcp setPulseDelay 10
  $rawTcp setPulseScript [list chatter::chat $chatScript $closeScript $rawTcp]
} -body {
  $rawTcp connect localhost $echoPort
  chatter::getMsg
} -cleanup {
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
    {send "this was sent from local"}
    {expect "ECHO: this was sent from local"}
    {closeServer {}}
    {expect "NO CARRIER"}
  }
  set closeScript {
    $rawTcp close
    $rawTcp setPulseDelay 0
    testHelpers::stopListening
  }
  $rawTcp setPulseDelay 10
  $rawTcp setPulseScript [list chatter::chat $chatScript $closeScript $rawTcp]
} -body {
  $rawTcp connect localhost $echoPort
  chatter::wait
  chatter::chat $chatScript $closeScript $rawTcp
  chatter::getMsg
} -cleanup {
  testHelpers::destroyFakeModem
  chatter::close
} -result {no errors}


cleanupTests
