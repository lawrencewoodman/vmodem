package require tcltest
namespace import tcltest::*

# Add module dir to tm paths
set ThisScriptDir [file dirname [info script]]
set LibDir [file normalize [file join $ThisScriptDir .. lib]]

source [file join $LibDir "logger.tcl"]


test dumpBytes-1 {Returns correctly formatted dump} -setup {
  set text "hello how are you\r"
  set bytes [split $text {}]
} -body {
  logger::dumpBytes $bytes
} -result {    0x0000:  6865 6c6c 6f20 686f 7720 6172 6520 796f  hello how are yo
 0x0010: 750d                                     u.}

cleanupTests
