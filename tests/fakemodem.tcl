
::oo::class create FakeModem {
  variable transport
  variable localInChannel
  variable localOutChannel
  variable oldLocalInReadableEventScript


  constructor {_localInChannel _localOutChannel} {
    set localInChannel $_localInChannel
    set localOutChannel $_localOutChannel
    set selfObject [self object]

    set oldLocalInReadableEventScript [
      chan event $localInChannel readable
    ]
    chan event $localInChannel readable [
      list ${selfObject}::my ReceiveFromLocal
    ]
  }

  destructor {
    chan event $localInChannel readable $oldLocalInReadableEventScript
  }


  method sendToLocal {dataForLocal} {
    puts -nonewline $localOutChannel $dataForLocal
  }


  method connected {} {
    puts $localOutChannel "CONNECT 1200\r\n"
  }


  method disconnected {} {
    puts $localOutChannel "NO CARRIER\r\n"
  }


  method setTransport {transportInst} {
    set transport $transportInst
  }


  method ring {} {
    my sendToLocal "RING\r\n"
  }


  method failedToConnect {} {
    puts $localOutChannel "NO CARRIER\r\n"
  }


  method isOnline {} {
    return true
  }


  method ReceiveFromLocal {} {
    if {[catch {read $localInChannel} dataFromLocal]} {
      return -code error "Couldn't read from local"
    }

    $transport sendLocalToRemote $dataFromLocal
  }
}
