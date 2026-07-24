import Foundation

// Startup gating before the GUI boots:
Bootstrap.detachFromTerminalIfNeeded() // return the shell prompt; run independently
Bootstrap.enforceSingleInstance()      // a second launch does nothing

MonitorOverlayApp.main()
