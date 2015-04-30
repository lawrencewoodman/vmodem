package require tcltest
namespace import tcltest::*
package require fileutil

# Add module dir to tm paths
set ThisScriptDir [file dirname [info script]]
set LibDir [file normalize [file join $ThisScriptDir .. lib]]

source [file join $ThisScriptDir "test_helpers.tcl"]
source [file join $LibDir "logger.tcl"]


test log-1 {Ensure can log the same non-error message multiple times in a row} -setup {
  set tmpFilename [::fileutil::tempfile "logger.test_"]
  logger::init $tmpFilename
} -body {
  logger::log info "this is an original message"
  logger::log info "this is will be a duplicate message"
  logger::log info "this is will be a duplicate message"
  logger::log info "this is almost an original message"
  logger::log notice "this is will be a duplicate message"
  logger::log notice "this is will be a duplicate message"
  logger::log info "but not this one"
  logger::close
  testHelpers::readLogToList $tmpFilename
} -result {{info {this is an original message}} {info {this is will be a duplicate message}} {info {this is will be a duplicate message}} {info {this is almost an original message}} {notice {this is will be a duplicate message}} {notice {this is will be a duplicate message}} {info {but not this one}}}


test log-2 {Ensure can't log the same error message multiple times in a row} -setup {
  set tmpFilename [::fileutil::tempfile "logger.test_"]
  logger::init $tmpFilename
} -body {
  logger::log error "this is an original message"
  logger::log error "this is will be a duplicate message"
  logger::log error "this is will be a duplicate message"
  logger::log error "but not this one"
  logger::close
  testHelpers::readLogToList $tmpFilename
} -result  {{error {this is an original message}} {error {this is will be a duplicate message}} {error {but not this one}}}


test log-3 {Ensure can't log the same critical message multiple times in a row} -setup {
  set tmpFilename [::fileutil::tempfile "logger.test_"]
  logger::init $tmpFilename
} -body {
  logger::log critical "this is an original message"
  logger::log critical "this is will be a duplicate message"
  logger::log critical "this is will be a duplicate message"
  logger::log critical "but not this one"
  logger::close
  testHelpers::readLogToList $tmpFilename
} -result  {{critical {this is an original message}} {critical {this is will be a duplicate message}} {critical {but not this one}}}


test dumpBytes-1 {Returns correctly formatted dump} -setup {
  set text "hello how are you\r"
  set bytes [split $text {}]
} -body {
  logger::dumpBytes $bytes
} -result {    0x0000:  6865 6c6c 6f20 686f 7720 6172 6520 796f  hello how are yo
    0x0010:  750d                                     u.}


cleanupTests
