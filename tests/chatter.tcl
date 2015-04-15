# Chat helper functions for the tests

namespace eval chatter {
  variable msg ""
  variable stage 0
  variable dataIn {}
  variable numDataIn 0
  variable inChannel
  variable outChannel
}


proc chatter::init {} {
  variable msg
  variable stage
  variable dataIn
  variable numDataIn
  variable inRead
  variable inWrite
  variable outRead
  variable outWrite

  lassign [chan pipe] inRead inWrite
  lassign [chan pipe] outRead outWrite
  chan configure $inRead -translation binary -blocking 0 -buffering none
  chan configure $inWrite -translation binary -blocking 0 -buffering none
  chan configure $outRead -translation binary -blocking 0 -buffering none
  chan configure $outWrite -translation binary -blocking 0 -buffering none
  chan event $outRead readable [list ::chatter::GetData $outRead]

  set msg ""
  set stage 0
  set dataIn {}
  set numDataIn 0
  return [list $inRead $outWrite]
}


proc chatter::close {} {
  variable inRead
  variable inWrite
  variable outRead
  variable outWrite

  ::close $inRead
  ::close $inWrite
  ::close $outRead
  ::close $outWrite
}


proc chatter::chat {chatScript closeScript transport} {
  variable msg
  variable stage
  variable inWrite
  variable outRead

  set maxStage [expr {[llength $chatScript] - 1}]
  set chatLine [lindex $chatScript $stage]
  lassign $chatLine action text

  switch $action {
    send {
      puts -nonewline $inWrite $text
    }
    sendBinary {
        puts -nonewline $inWrite [binary format c* $text]
    }
    expect {
      set dataIn [string trim [ReadData]]
      if {$dataIn ne $text} {
        set msg "stage: $stage expecting: $text, got: $dataIn"
      }
    }
    expectBinary {
      set dataIn [ReadData]
      binary scan $dataIn c* dataInText
      set dataInText [
        lmap byte $dataInText {
          set unsignedByte [expr {$byte & 0xff}]
          format {0x%02x} $unsignedByte
        }
      ]
      if {$dataInText ne $text} {
        set msg "stage: $stage expecting binary: $text, got: $dataInText"
      }
    }
    closeServer {
      ::testHelpers::closeRemote
    }
    default {
      return -code error "Unknown action: $action"
    }
  }

  incr stage

  if {$stage > $maxStage && $msg eq ""} {
    set msg "no errors"
  }

  if {$msg ne ""} {
    uplevel 1 $closeScript
    return
  }
}


proc chatter::getMsg {} {
  variable msg
  return $msg
}


proc chatter::wait {} {
  vwait ::chatter::numDataIn
}


proc chatter::GetData {channel} {
  variable dataIn
  variable numDataIn
  lappend dataIn [read $channel]
  incr numDataIn
}


proc chatter::ReadData {} {
  variable dataIn
  variable numDataIn

  if {$numDataIn > 0} {
    set data [lindex $dataIn end]
    set dataIn [lrange $dataIn 1 end]
    binary scan $data c* dataText
    set dataText [
      lmap b $dataText {
        set unsignedByte [expr {$b & 0xff}]
        format {%02x} $unsignedByte
      }
    ]

    incr numDataIn -1
    return $data
  } else {
    return ""
  }
}
