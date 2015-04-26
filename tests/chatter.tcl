# Chat helper functions for the tests

namespace eval chatter {
  variable dataIn {}
  variable numDataIn 0
  variable inRead
  variable inWrite
  variable outRead
  variable outWrite
  variable transport
}


proc chatter::init {{_transport {}}} {
  variable dataIn
  variable numDataIn
  variable inRead
  variable inWrite
  variable outRead
  variable outWrite
  variable transport

  set dataIn {}
  set numDataIn 0
  set transport $_transport

  if {$transport eq {}} {
    lassign [chan pipe] inRead inWrite
    lassign [chan pipe] outRead outWrite
    chan configure $inRead -translation binary -blocking 0 -buffering none
    chan configure $inWrite -translation binary -blocking 0 -buffering none
    chan configure $outRead -translation binary -blocking 0 -buffering none
    chan configure $outWrite -translation binary -blocking 0 -buffering none
    chan event $outRead readable [list ::chatter::GetData $outRead]

    return [list $inRead $outWrite]
  }
}


proc chatter::close {} {
  variable inRead
  variable inWrite
  variable outRead
  variable outWrite
  variable transport

  if {$transport ne {}} {
    ::close $inRead
    ::close $inWrite
    ::close $outRead
    ::close $outWrite
  }
}


proc chatter::chat {chatScript} {
  variable inWrite
  variable outRead
  set maxStage [expr {[llength $chatScript] - 1}]
  set msg ""
  set oldStage 0
  set stage 0
  set pulse 0
  set finished 0
  set timeoutSecs 3
  set timeSinceNewStage [clock seconds]


  while {$msg eq ""} {
    after 10 [list set ::chatter::pulse 1]
    vwait ::chatter::pulse
    set pulse 0

    set chatLine [lindex $chatScript $stage]
    lassign $chatLine action text
    lassign [handleAction $action $text $stage] stage msg

    if {$stage > $oldStage} {
      set timeSinceNewStage [clock seconds]
      set oldStage $stage
    } else {
      set currentTime [clock seconds]
      if {$currentTime - $timeSinceNewStage > $timeoutSecs} {
        set msg "Timeout - $stage: $action $text"
      }
    }

    if {$stage > $maxStage && $msg eq ""} {
      set msg "no errors"
    }
  }

  return $msg
}


proc chatter::handleAction {action text stage} {
  variable transport
  set msg ""

  switch $action {
    send {
      SendData $text
      incr stage

    }
    sendBinary {
      SendData [binary format c* $text]
      incr stage
    }
    expect {
      set dataIn [ReadData]
      if {$dataIn ne ""} {
        if {$dataIn ne $text} {
          set msg "stage: $stage expecting: $text, got: $dataIn"
        }
        incr stage
      }
    }
    expectBinary {
      set expectedNumBytes [llength $text]
      set dataIn [ReadData $expectedNumBytes]
      if {$dataIn ne ""} {
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
        incr stage
      }
    }
    pause {
      after $text
      incr stage
    }
    getMessage {
      set latestMessage [$transport getMessage]
      if {$latestMessage ne {}} {
        if {$latestMessage ne $text} {
          set msg "stage: $stage expecting transport getMessage: $text, got: $latestMessage"
        }
      }
      incr stage
    }
    default {
      return -code error "Unknown action: $action"
    }
  }

  return [list $stage $msg]
}


proc chatter::GetData {channel} {
  variable dataIn
  variable numDataIn
  set line ""

  set data [read $channel]

  for {set i 0} {$i < [string length $data]} {incr i} {
    set ch [string index $data $i]
    append line $ch
    if {$ch eq "\n"} {
      if {[string trim $line] ne ""} {
        lappend dataIn $line
        incr numDataIn
      }
      set line ""
    }
  }

  if {[string trim $line] ne ""} {
    lappend dataIn $line
    incr numDataIn
  }
}


proc chatter::SendData {dataToSend} {
  variable inWrite
  variable transport

  if {$transport ne {}} {
    $transport sendLocalToRemote $dataToSend
  } else {
    puts -nonewline $inWrite $dataToSend
  }
}


proc chatter::ReadData {{numBytes 0}} {
  variable transport

  if {$transport ne {}} {
    ReadDataViaTransport $numBytes
  } else {
    ReadDataViaChannel $numBytes
  }
}


proc chatter::ReadDataViaTransport {{numBytes 0}} {
  variable transport
  $transport getDataForLocal $numBytes
}


proc chatter::ReadDataViaChannel {{numBytes 0}} {
  variable dataIn
  variable numDataIn

  if {$numDataIn > 0} {
    set data [lindex $dataIn 0]
    if {$numBytes == 0} {
      set dataToReturn $data
      set dataIn [lrange $dataIn 1 end]
      incr numDataIn -1
    } else {
      set dataToReturn [string range $data 0 [expr {$numBytes - 1}]]
      set dataLeft [string range $data $numBytes end]

      if {$dataLeft ne ""} {
        lset dataIn 0 $dataLeft
      } else {
        set dataIn [lrange $dataIn 1 end]
        incr numDataIn -1
      }
    }

    return $dataToReturn
  } else {
    return ""
  }
}
