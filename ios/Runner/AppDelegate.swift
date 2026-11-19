import Flutter
import UIKit
import StoreKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var channel: FlutterMethodChannel?
  private var pending: [String: Transaction] = [:]
  private var updates: Task<Void, Never>?
  override func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "BasecocStoreKit")!
    let c = FlutterMethodChannel(name: "basecoc/storekit", binaryMessenger: registrar.messenger())
    channel = c
    c.setMethodCallHandler { [weak self] call, result in
      Task { @MainActor in
        guard let self = self else { result(FlutterError(code: "unavailable", message: nil, details: nil)); return }
        do { try await self.handle(call, result) }
        catch { result(FlutterError(code: "storekit", message: error.localizedDescription, details: nil)) }
      }
    }
    updates = Task { @MainActor [weak self] in
      for await item in Transaction.updates {
        if case .verified(let tx) = item, let self = self {
          self.channel?.invokeMethod("transaction", arguments: self.encode(tx))
        }
      }
    }
  }
  @MainActor private func encode(_ tx: Transaction) -> [String: Any] {
    let id = String(tx.id)
    pending[id] = tx
    var environment = "Unknown"
    if #available(iOS 16.0, *) {
      if tx.environment == .sandbox {
        environment = "Sandbox"
      } else if tx.environment == .production {
        environment = "Production"
      }
    } else if let payload = try? JSONSerialization.jsonObject(with: tx.jsonRepresentation) as? [String: Any],
              let env = payload["environment"] as? String {
      if env == "Sandbox" || env == "Production" {
        environment = env
      }
    }
    return ["transaction_id": id, "environment": environment]
  }
  @MainActor private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) async throws {
    let args = call.arguments as? [String: Any] ?? [:]
    let ids = ["premium_monthly", "premium_yearly"]
    switch call.method {
    case "products":
      let products = try await Product.products(for: ids)
      result(products.map { ["id": $0.id, "name": $0.displayName, "price": $0.displayPrice] })
    case "buy":
      guard let id = args["id"] as? String, ids.contains(id), let token = args["token"] as? String, let uuid = UUID(uuidString: token), let product = try await Product.products(for: [id]).first else {
        result(FlutterError(code: "invalid_product", message: nil, details: nil)); return
      }
      switch try await product.purchase(options: [.appAccountToken(uuid)]) {
      case .success(let verification):
        if case .verified(let tx) = verification { result(encode(tx)) }
        else { result(FlutterError(code: "unverified", message: nil, details: nil)) }
      case .pending: result(nil)
      case .userCancelled: result(nil)
      @unknown default: result(nil)
      }
    case "restore", "entitlements":
      if call.method == "restore" { try await AppStore.sync() }
      var rows: [[String: Any]] = []
      for await item in Transaction.currentEntitlements {
        if case .verified(let tx) = item, ids.contains(tx.productID) { rows.append(encode(tx)) }
      }
      result(rows)
    case "finish":
      if let id = args["transaction_id"] as? String, let tx = pending.removeValue(forKey: id) { await tx.finish() }
      result(nil)
    default: result(FlutterMethodNotImplemented)
    }
  }
}
