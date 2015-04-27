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
source [file join $LibDir "telnet.tcl"]


test connect-1 {Report as connected when connected} -setup {
  set echoPort [testHelpers::listen]
  set telnet [Telnet new 0 0]
  chatter::init $telnet
  set chatScript {
    {getMessage "connecting"}
    {getMessage "connected"}
  }
} -body {
  $telnet connect localhost $echoPort
  chatter::chat $chatScript
} -cleanup {
  $telnet stopListening
  $telnet close
  testHelpers::stopListening
  testHelpers::closeRemote
} -result {no errors}


test connect-2 {Reports failed to connect when failed to connect} -setup {
  set unusedPort [testHelpers::findUnusedPort]
  set telnet [Telnet new 0 0]
  chatter::init $telnet
  set chatScript {
    {getMessage "connecting"}
    {getMessage "connectionFailed"}
  }
} -body {
  $telnet connect localhost $unusedPort
  chatter::chat $chatScript
} -cleanup {
  $telnet stopListening
} -result {no errors}


test connect-3 {Check can send and receive data} -setup {
  set telnet [Telnet new 0 0]
  chatter::init $telnet
  set echoPort [testHelpers::listen]

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
  $telnet connect localhost $echoPort
  chatter::chat $chatScript
} -cleanup {
  $telnet stopListening
  $telnet close
  testHelpers::stopListening
  testHelpers::closeRemote
} -result {no errors}


test connect-4 {Check detects when remote connection has dropped and reports it} -setup {
  set echoPort [testHelpers::listen]
  set telnet [Telnet new 0 0]
  chatter::init $telnet
  set chatScript {
    {getMessage "connecting"}
    {getMessage "connected"}
    {pause 200}
    {getMessage "connectionClosed"}
  }
} -body {
  $telnet connect localhost $echoPort
  after 100 ::testHelpers::closeRemote
  chatter::chat $chatScript
} -cleanup {
  $telnet stopListening
  $telnet close
  testHelpers::stopListening
} -result {no errors}


test connect-5 {Check will escape 0xFF when sent} -setup {
  set telnet [Telnet new 0 0]
  chatter::init $telnet
  set decrPort [testHelpers::listen decr]

  set chatScript {
    {getMessage "connecting"}
    {getMessage "connected"}
    {sendBinary {0x23 0xff 0x44}}
    {expectBinary {0x22 0xfe 0xfe 0x43}}
  }
} -body {
  $telnet connect localhost $decrPort
  chatter::chat $chatScript
} -cleanup {
  $telnet stopListening
  $telnet close
  testHelpers::stopListening
  testHelpers::closeRemote
} -result {no errors}


test connect-6 {Check will recognize escaped 0xFF when received} -setup {
  set decrPort [testHelpers::listen decr]
  set telnet [Telnet new 0 0]
  chatter::init $telnet

  set chatScript {
    {getMessage "connecting"}
    {getMessage "connected"}
    {sendBinary {0x23 0x00 0x00 0x44}}
    {expectBinary {0x22 0xff 0x43}}
  }
} -body {
  $telnet connect localhost $decrPort
  chatter::chat $chatScript
} -cleanup {
  $telnet stopListening
  $telnet close
  testHelpers::stopListening
  testHelpers::closeRemote
} -result {no errors}


test connect-7 {Will handle telnet negotations properly and ensure that server WILL ECHO} -setup {
  # This server will negotiate telnet options, but will escape any IACs
  # and send them back for reviewing.
  set echoPort [testHelpers::listen telnet]
  set telnet [Telnet new 0 0]
  chatter::init $telnet

  set telnetCodesMap {
    {WILL } {0xfb }
    {WONT } {0xfc }
    {DO } {0xfd }
    {DONT } {0xfe }
    {IAC } {0xff }
    {ECHO} 0x01
    {SUPRESS_GO_AHEAD} 0x03
    {LINEMODE} 0x34
  }
  set chatScript [
    string map $telnetCodesMap {
                 {getMessage "connecting"}
                 {getMessage "connected"}
                 {expectBinary {IAC DO ECHO}}
                 {expectBinary {IAC DO ECHO}}
                 {expectBinary {IAC DONT SUPRESS_GO_AHEAD}}
                 {expectBinary {IAC WONT LINEMODE}}
                 {send "hello\r\n"}
                 {expect "hello\r\n"}
               }
  ]
} -body {
  $telnet connect localhost $echoPort
  chatter::chat $chatScript
} -cleanup {
  $telnet stopListening
  $telnet close
  testHelpers::stopListening
  testHelpers::closeRemote
} -result {no errors}


test listen-1 {Reports as connected when local in bound connection made} -setup {
  set telnet [Telnet new 0 0]
  chatter::init $telnet
  set chatScript {
    {getMessage "connecting"}
    {getMessage "connected"}
  }
} -body {
  set port 1024

  while {![$telnet listen $port]} {
    incr port
  }

  testHelpers::connect $port
  chatter::chat $chatScript
} -cleanup {
  $telnet stopListening
  $telnet close
  testHelpers::closeRemote
} -result {no errors}


test listen-2 {Reports as ringing when receives connection if requested} -setup {
  set telnet [Telnet new 1 0]
  chatter::init $telnet
  set chatScript {
    {getMessage "ringing"}
    {getMessage "connecting"}
    {getMessage "connected"}
  }
} -body {
  set port 1024

  while {![$telnet listen $port]} {
    incr port
  }

  testHelpers::connect $port
  chatter::chat $chatScript
} -cleanup {
  $telnet stopListening
  $telnet close
  testHelpers::closeRemote
} -result {no errors}


cleanupTests
