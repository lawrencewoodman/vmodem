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


test connect-1 {Reports as connected when connected} -setup {
  set echoPort [testHelpers::listen]
  set rawTcp [RawTcp new 0 0]
  chatter::init $rawTcp
  set chatScript {
    {getMessage "connecting"}
    {getMessage "connected"}
  }
} -body {
  $rawTcp connect localhost $echoPort
  chatter::chat $chatScript
} -cleanup {
  $rawTcp stopListening
  $rawTcp close
  testHelpers::stopListening
  testHelpers::closeRemote
} -result {no errors}


test connect-2 {Reports failed to connect when failed to connect} -setup {
  set unusedPort [testHelpers::findUnusedPort]
  set rawTcp [RawTcp new 0 0]
  chatter::init $rawTcp
  set chatScript {
    {getMessage "connecting"}
    {getMessage "connectionFailed"}
  }
} -body {
  $rawTcp connect localhost $unusedPort
  chatter::chat $chatScript
} -cleanup {
  $rawTcp stopListening
} -result {no errors}


test connect-3 {Check can send and receive data} -setup {
  set echoPort [testHelpers::listen]
  set rawTcp [RawTcp new 0 0]
  chatter::init $rawTcp
  set chatScript {
    {getMessage "connecting"}
    {getMessage "connected"}
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
  $rawTcp stopListening
  $rawTcp close
  testHelpers::stopListening
  testHelpers::closeRemote
} -result {no errors}


test connect-4 {Check detects when remote connection has dropped and reports it} -setup {
  set echoPort [testHelpers::listen]
  set rawTcp [RawTcp new 0 0]
  chatter::init $rawTcp
  set chatScript {
    {getMessage "connecting"}
    {getMessage "connected"}
    {getMessage "connectionClosed"}
  }
} -body {
  $rawTcp connect localhost $echoPort
  after 100 ::testHelpers::closeRemote
  chatter::chat $chatScript
} -cleanup {
  $rawTcp stopListening
  $rawTcp close
  testHelpers::stopListening
} -result {no errors}


test listen-1 {Reports as connected when local in bound connection made} -setup {
  set rawTcp [RawTcp new 0 0]
  chatter::init $rawTcp
  set chatScript {
    {getMessage "connecting"}
    {getMessage "connected"}
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
  $rawTcp stopListening
  $rawTcp close
  testHelpers::closeRemote
} -result {no errors}


test listen-2 {Reports as ringing when receives connection if requested} -setup {
  set rawTcp [RawTcp new 1 0]
  chatter::init $rawTcp
  set chatScript {
    {getMessage "ringing"}
    {getMessage "connecting"}
    {getMessage "connected"}
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
  $rawTcp stopListening
  $rawTcp close
  testHelpers::closeRemote
} -result {no errors}



cleanupTests
