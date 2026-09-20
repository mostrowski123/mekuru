import Flutter
import ImageIO
import UIKit
import UniformTypeIdentifiers
import Vision
import onnxruntime_objc

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    registerStorageChannel(messenger: engineBridge.applicationRegistrar.messenger())
    registerVisionOcrChannel(messenger: engineBridge.applicationRegistrar.messenger())
    FilesBridge.shared.register(messenger: engineBridge.applicationRegistrar.messenger())
  }

  /// `mekuru/vision_ocr`: the text lines Apple Vision finds and reads on one
  /// manga page, as `{width, height, lines: [{box: [x0, y0, x1, y1], text}]}`
  /// in page pixels from the top-left. Dart groups the lines into blocks
  /// (`vision_block_grouping.dart`). This is the iOS stand-in for the Android
  /// detector; use the Swift `RecognizeTextRequest`, not `VNRecognizeTextRequest`,
  /// which barely sees vertical Japanese (measured with tools/vision_recall.swift).
  private func registerVisionOcrChannel(messenger: FlutterBinaryMessenger) {
    FlutterMethodChannel(name: "mekuru/vision_ocr", binaryMessenger: messenger)
      .setMethodCallHandler { call, result in
        if call.method.hasPrefix("mangaOcr") {
          MangaOcrModel.shared.handle(call, result: result)
          return
        }
        guard call.method == "recognizeLines",
          let bytes = (call.arguments as? FlutterStandardTypedData)?.data
        else {
          result(FlutterMethodNotImplemented)
          return
        }
        Task.detached(priority: .userInitiated) {
          let reply: Any
          do {
            guard let source = CGImageSourceCreateWithData(bytes as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
            else {
              throw NSError(
                domain: "mekuru.vision_ocr", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "The page image could not be decoded."])
            }
            var request = RecognizeTextRequest()
            request.recognitionLanguages = [Locale.Language(identifier: "ja-JP")]
            request.recognitionLevel = .accurate
            // Vision's default skips text under 1/32 of the image height,
            // which is most lettering on a full manga page.
            request.minimumTextHeightFraction = 0
            let (w, h) = (Double(image.width), Double(image.height))
            let lines = try await request.perform(on: image).map { line -> [String: Any] in
              // Normalised, origin bottom-left.
              let r = line.boundingBox.cgRect
              return [
                "box": [r.minX * w, (1 - r.maxY) * h, r.maxX * w, (1 - r.minY) * h],
                "text": line.topCandidates(1).first?.string ?? "",
              ]
            }
            reply = ["width": image.width, "height": image.height, "lines": lines]
          } catch {
            reply = FlutterError(
              code: "vision_failed", message: error.localizedDescription, details: nil)
          }
          await MainActor.run { result(reply) }
        }
      }
  }

  /// `mekuru/ios_storage`: keeps re-downloadable data (MeCab dictionaries,
  /// KanjiVG) out of iCloud/device backups, which App Review requires.
  private func registerStorageChannel(messenger: FlutterBinaryMessenger) {
    FlutterMethodChannel(name: "mekuru/ios_storage", binaryMessenger: messenger)
      .setMethodCallHandler { call, result in
        guard call.method == "excludeFromBackup", let paths = call.arguments as? [String] else {
          result(FlutterMethodNotImplemented)
          return
        }
        do {
          for path in paths {
            var url = URL(fileURLWithPath: path)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try url.setResourceValues(values)
          }
          result(nil)
        } catch {
          result(FlutterError(code: "exclude_failed", message: error.localizedDescription, details: nil))
        }
      }
  }
}

/// The manga-ocr model on ONNX Runtime, as thin as it can be: Dart prepares
/// the pixels, runs the greedy decoding loop and cleans the text
/// (`manga_ocr_algorithms.dart`, shared test vectors with Android); this only
/// runs the two sessions. One encode, then one step per token, all on a
/// serial queue. ponytail: lives here to avoid a plugin for one class; move it
/// into `packages/local_manga_ocr/ios` if the iOS side grows.
final class MangaOcrModel {
  static let shared = MangaOcrModel()

  private let queue = DispatchQueue(label: "mekuru.manga_ocr")
  private var env: ORTEnv?
  private var encoder: ORTSession?
  private var decoder: ORTSession?
  private var hiddenStates: ORTValue?

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    queue.async {
      let reply: Any?
      do {
        reply = try self.run(call)
      } catch {
        reply = FlutterError(code: "manga_ocr_failed", message: error.localizedDescription, details: nil)
      }
      DispatchQueue.main.async { result(reply) }
    }
  }

  private func run(_ call: FlutterMethodCall) throws -> Any? {
    switch call.method {
    case "mangaOcrLoad":
      guard let args = call.arguments as? [String: String],
        let encoderPath = args["encoder"], let decoderPath = args["decoder"]
      else { return FlutterMethodNotImplemented }
      if encoder == nil {
        let env = try ORTEnv(loggingLevel: .warning)
        let options = try ORTSessionOptions()
        encoder = try ORTSession(env: env, modelPath: encoderPath, sessionOptions: options)
        decoder = try ORTSession(env: env, modelPath: decoderPath, sessionOptions: options)
        self.env = env
      }
      return true
    case "mangaOcrUnload":
      (encoder, decoder, hiddenStates, env) = (nil, nil, nil, nil)
      return nil
    case "mangaOcrEncode":
      // float32 [1, 3, 224, 224], already normalised.
      guard let pixels = (call.arguments as? FlutterStandardTypedData)?.data, let encoder else {
        return FlutterMethodNotImplemented
      }
      let input = try ORTValue(
        tensorData: NSMutableData(data: pixels), elementType: .float, shape: [1, 3, 224, 224])
      hiddenStates = try encoder.run(
        withInputs: ["pixel_values": input], outputNames: ["last_hidden_state"], runOptions: nil
      )["last_hidden_state"]
      return nil
    case "mangaOcrStep":
      // The token ids so far; answers the logits for the next token.
      guard let ids = call.arguments as? [Int], let decoder, let hiddenStates else {
        return FlutterMethodNotImplemented
      }
      let idData = NSMutableData(length: ids.count * MemoryLayout<Int64>.size)!
      let idPointer = idData.mutableBytes.bindMemory(to: Int64.self, capacity: ids.count)
      for (i, id) in ids.enumerated() { idPointer[i] = Int64(id) }
      let input = try ORTValue(
        tensorData: idData, elementType: .int64, shape: [1, NSNumber(value: ids.count)])
      let logits = try decoder.run(
        withInputs: ["input_ids": input, "encoder_hidden_states": hiddenStates],
        outputNames: ["logits"], runOptions: nil)["logits"]!
      // [1, ids.count, vocabulary]: keep the last position only.
      let all = try logits.tensorData() as Data
      let vocabulary = all.count / MemoryLayout<Float>.size / ids.count
      let last = all.suffix(vocabulary * MemoryLayout<Float>.size)
      return FlutterStandardTypedData(float32: Data(last))
    default:
      return FlutterMethodNotImplemented
    }
  }
}

/// `mekuru/ios_files`: the document-picker calls full backup needs, which no
/// plugin in the app offers without pulling a multi-gigabyte file into memory.
///  - `exportFile(path)`: lets the user choose where the file goes and MOVES
///    it there (no second copy on disk). True when moved, false if cancelled.
///  - `pickZip()`: a local copy of the zip the user picked, or nil. The caller
///    deletes the copy when done.
///  - `freeBytes()`: space the system is willing to give the app.
final class FilesBridge: NSObject, UIDocumentPickerDelegate {
  static let shared = FilesBridge()
  private var pending: FlutterResult?
  private var exporting = false

  func register(messenger: FlutterBinaryMessenger) {
    FlutterMethodChannel(name: "mekuru/ios_files", binaryMessenger: messenger)
      .setMethodCallHandler { [weak self] call, result in
        guard let self else { return }
        switch call.method {
        case "exportFile":
          guard let path = call.arguments as? String else { return result(FlutterMethodNotImplemented) }
          self.present(
            UIDocumentPickerViewController(forExporting: [URL(fileURLWithPath: path)], asCopy: false),
            exporting: true, result: result)
        case "pickZip":
          self.present(
            UIDocumentPickerViewController(forOpeningContentTypes: [.zip], asCopy: true),
            exporting: false, result: result)
        case "freeBytes":
          let values = try? URL(fileURLWithPath: NSHomeDirectory())
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
          result(values?.volumeAvailableCapacityForImportantUsage)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
  }

  private func present(_ picker: UIDocumentPickerViewController, exporting: Bool, result: @escaping FlutterResult) {
    guard pending == nil,
      var top = UIApplication.shared.connectedScenes
        .compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first?.rootViewController
    else {
      return result(FlutterError(code: "picker_unavailable", message: nil, details: nil))
    }
    while let presented = top.presentedViewController { top = presented }
    pending = result
    self.exporting = exporting
    picker.delegate = self
    top.present(picker, animated: true)
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    pending?(exporting ? true : urls.first?.path)
    pending = nil
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    pending?(exporting ? false : nil)
    pending = nil
  }
}
