import AVFoundation
import Flutter
import UIKit

/// First-frame thumbnails and durations for the upload flow.
///
/// `VideoThumbnails` on the Dart side asks this channel for a JPEG before it
/// uploads a video, because the worker stores the still beside the media and the
/// library reads it back through `/api/video-proxy`. Without it every uploaded
/// shiur reached the library with no thumbnail. Ported from `ShiurUploader.swift`
/// in the native app so both produce the same frame at the same size.
enum VideoThumbnailChannel {
  private static let channelName = "beisanytime/video_thumbnail"

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      let arguments = call.arguments as? [String: Any] ?? [:]
      guard let path = arguments["path"] as? String else {
        if call.method == "createThumbnail" || call.method == "durationMs" {
          // A missing frame or duration is not a failure: an upload without a
          // thumbnail is still a valid upload, and Dart treats nil that way.
          result(nil)
        } else {
          result(FlutterMethodNotImplemented)
        }
        return
      }
      let url = URL(fileURLWithPath: path)

      switch call.method {
      case "createThumbnail":
        let seconds = Double(arguments["timeMs"] as? Int ?? 1000) / 1000
        let maxWidth = CGFloat(arguments["maxWidth"] as? Int ?? 1280)
        Task {
          let jpeg = await thumbnailJPEG(from: url, at: seconds, maxWidth: maxWidth)
          await MainActor.run {
            result(jpeg.map { FlutterStandardTypedData(bytes: $0) })
          }
        }

      case "durationMs":
        Task {
          let seconds = await duration(of: url)
          await MainActor.run { result(Int((seconds * 1000).rounded())) }
        }

      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// Duration of a video or audio file, or 0 when it cannot be read.
  private static func duration(of url: URL) async -> Double {
    let asset = AVURLAsset(url: url)
    guard let duration = try? await asset.load(.duration) else { return 0 }
    let seconds = duration.seconds
    return seconds.isFinite && seconds > 0 ? seconds : 0
  }

  /// Grabs a frame and encodes it as JPEG, matching what the web app uploads.
  private static func thumbnailJPEG(
    from url: URL,
    at seconds: Double,
    maxWidth: CGFloat
  ) async -> Data? {
    let asset = AVURLAsset(url: url)
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = CGSize(width: maxWidth, height: maxWidth)
    generator.requestedTimeToleranceBefore = CMTime(seconds: 1, preferredTimescale: 600)
    generator.requestedTimeToleranceAfter = CMTime(seconds: 1, preferredTimescale: 600)

    let time = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
    guard let (image, _) = try? await generator.image(at: time) else { return nil }
    return UIImage(cgImage: image).jpegData(compressionQuality: 0.8)
  }
}
