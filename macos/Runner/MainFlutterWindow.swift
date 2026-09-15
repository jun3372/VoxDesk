import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    // 默认 1280x800；小屏幕上若超过屏幕可视区域（不含菜单栏和 Dock），
    // 启动时收缩为屏幕可视大小，避免窗口超出屏幕
    let defaultSize = NSSize(width: 1280, height: 800)
    var windowSize = defaultSize
    if let visibleSize = NSScreen.main?.visibleFrame.size {
      windowSize = NSSize(
        width: min(defaultSize.width, visibleSize.width),
        height: min(defaultSize.height, visibleSize.height)
      )
    }
    self.contentViewController = flutterViewController
    self.setFrame(
      NSRect(x: 0, y: 0, width: windowSize.width, height: windowSize.height),
      display: true
    )
    // 禁用系统窗口状态恢复：否则 macOS 会在启动约 1s 后用上次会话保存的
    // frame（可能超出当前屏幕或为最大化状态）覆盖上面的初始大小
    self.isRestorable = false
    self.contentMinSize = NSSize(width: 980, height: 640)

    // 透明标题栏：内容延伸至标题栏区域（fullSizeContentView），保留交通灯按钮
    self.titlebarAppearsTransparent = true
    self.titleVisibility = .hidden
    self.styleMask.insert(.fullSizeContentView)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
