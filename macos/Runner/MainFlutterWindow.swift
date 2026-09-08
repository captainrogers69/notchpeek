import Cocoa
import FlutterMacOS

/// The nib instantiates this window and nothing is ever drawn in it. It owns
/// no engine and no view controller: `AppDelegate` builds the engine headless
/// and hands its view controller to `NotchWindowController`'s panel.
///
/// Creating the view controller here and moving it into the panel later is
/// what broke the panel's `devicePixelRatio` — see the comment in
/// `AppDelegate.start()`. Do not put a `FlutterViewController` back in here.
class MainFlutterWindow: NSWindow {

  override func awakeFromNib() {
    super.awakeFromNib()
    setIsVisible(false)
    orderOut(nil)
  }
}
