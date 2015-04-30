vmodem
======
A modem emulator

Emulate a modem so that applications such as vice can use it to connect to machines across the internet as if they were dialling a phone number on a modem.

Requirements
------------
*  Tcl 8.6
*  [Tcllib](http://core.tcl.tk/tcllib/home)
*  [TclX](http://sourceforge.net/projects/tclx/)
*  [pty](https://github.com/LawrenceWoodman/pty_tcl) optional package if you want to use a pseudo TTY
*  [AppDirs](https://github.com/LawrenceWoodman/appdirs_tcl) module
*  [configurator](https://github.com/LawrenceWoodman/configurator_tcl) module

Usage
-----
Communicate with the program via stdin/stdout by default or a pseudo TTY if requested.  So in vice you can specify it as the program to exec in the RS232 settings.

Contributions
-------------
If you want to improve this program make a pull request to the [repo](https://github.com/LawrenceWoodman/vmodem) on github.  Please put any pull requests in a separate branch to ease integration and add a test to prove that it works.

Licence
-------
Copyright (C) 2015, Lawrence Woodman <lwoodman@vlifesystems.com>

This software is licensed under an MIT Licence.  Please see the file, LICENCE.md, for details.
