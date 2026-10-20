import Cocoa
import FlutterMacOS
import UniformTypeIdentifiers

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

    SavePanelPlugin.register(
      with: flutterViewController.registrar(forPlugin: "SavePanelPlugin")
    )

    super.awakeFromNib()
  }
}

/// 显示完整扩展名的保存面板（channel: voxdesk/save_panel）。
/// file_picker 的 NSSavePanel 固定 isExtensionHidden=true，导出对话框的
/// 默认文件名看不到后缀；导出走此面板让用户看到完整文件名。
/// 协议：方法 save，参数 fileName / dialogTitle，返回所选路径或 null（取消）。
class SavePanelPlugin: NSObject, FlutterPlugin {
  private weak var registrar: FlutterPluginRegistrar?

  static func register(with registrar: FlutterPluginRegistrar) {
    let instance = SavePanelPlugin()
    instance.registrar = registrar
    let channel = FlutterMethodChannel(
      name: "voxdesk/save_panel",
      binaryMessenger: registrar.messenger
    )
    registrar.addMethodCallHandler(instance, channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "save", let args = call.arguments as? [String: Any] else {
      result(FlutterMethodNotImplemented)
      return
    }
    let panel = NSSavePanel()
    let title = args["dialogTitle"] as? String ?? ""
    panel.title = title
    panel.message = title
    panel.canCreateDirectories = true
    panel.showsTagField = false
    panel.isExtensionHidden = false
    let fileName = args["fileName"] as? String ?? ""
    panel.nameFieldStringValue = fileName
    // 限定内容类型：用户只改名字时保存阶段仍会自动补上正确后缀
    let ext = (fileName as NSString).pathExtension
    if #available(macOS 11.0, *) {
      if let type = ext.isEmpty ? nil : UTType(filenameExtension: ext) {
        panel.allowedContentTypes = [type]
      }
    } else if !ext.isEmpty {
      panel.allowedFileTypes = [ext]
    }
    guard let window = registrar?.view?.window else {
      result(nil)
      return
    }
    panel.beginSheetModal(for: window) { response in
      result(response == .OK ? panel.url?.path : nil)
    }
  }
}
