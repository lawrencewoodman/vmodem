#
# Handle the phonebook
#
# Copyright (C) 2015 Lawrence Woodman <lwoodman@vlifesystems.com>
#
# Licensed under an MIT licence.  Please see LICENCE.md for details.
#
package require TclOO
package require configurator
namespace import configurator::*

::oo::class create Phonebook {
  variable phonebook

  constructor {{phonebookConfig {}}} {
    if {$phonebookConfig ne {}} {
      set phonebook [parseConfig $phonebookConfig]
    } else {
      set phonebook [dict create]
    }
  }


  method loadNumbersFromFile {filename} {
    if {[catch {open $filename r} fid]} {
      logger::log warning "Couldn't open file $filename, not using phonebook"
      set phonebook {}
    } else {
      set phonebookContents [read $fid]
      close $fid
      set phonebook [parseConfig $phonebookContents]
    }
  }


  method lookupPhoneNumber {phoneNumber} {
    set defaults {
      port 23
      speed 1200
      type telnet
    }
    if {[dict exists $phonebook $phoneNumber]} {
      set phoneNumberRecord [dict get $phonebook $phoneNumber]
      dict create \
        hostname [dict get $phoneNumberRecord hostname] \
        port [my DictGetOrDefault $phoneNumberRecord port $defaults] \
        speed [my DictGetOrDefault $phoneNumberRecord speed $defaults] \
        type [my DictGetOrDefault $phoneNumberRecord type $defaults]
    } else {
      return {}
    }
  }



  #############################
  #  Internal methods
  #############################

  method DictGetOrDefault {dictionary key defaults} {
    if {[dict exists $dictionary $key]} {
      return [dict get $dictionary $key]
    }

    return [dict get $defaults $key]
  }
}

