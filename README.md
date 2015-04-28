vmodem
======
A modem emulator

Emulate a modem so that applications such as vice can use it to connect to machines across the internet as if they were dialling a phone number on a modem.

Requirements
------------
*  Tcl 8.5+
*  [Tcllib](http://core.tcl.tk/tcllib/home)
*  [TclOO](http://core.tcl.tk/tcloo/wiki?name=TclOO+Package) (Included as part of the core distribution from Tcl 8.6)
*  [TclX](http://sourceforge.net/projects/tclx/)
*  [AppDirs](https://github.com/LawrenceWoodman/appdirs_tcl) module
*  [configurator](https://github.com/LawrenceWoodman/configurator_tcl) module

Usage
-----
Communicate with the program via stdin/stdout.  So in vice you can specify it as the program to exec in the RS232 settings.

Contributions
-------------
If you want to improve this module make a pull request to the [repo](https://github.com/LawrenceWoodman/vmodem) on github.  Please put any pull requests in a separate branch to ease integration and add a test to prove that it works.

Licence
-------
Copyright (C) 2015, Lawrence Woodman <lwoodman@vlifesystems.com>

This software is licensed under an MIT Licence.  Please see the file, LICENCE.md, for details.
