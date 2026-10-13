import Foundation
import CoreAudio
import AudioToolbox

struct Device: Codable {
    let uid: String
    let name: String
}

struct AudioFailure: Error {
    let message: String
}

func check(_ status: OSStatus, _ operation: String) throws {
    if status != noErr { throw AudioFailure(message: "\(operation) failed (\(status))") }
}

func stringProperty(_ id: AudioObjectID, _ selector: AudioObjectPropertySelector) throws -> String {
    var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var value: CFString = "" as CFString
    var size = UInt32(MemoryLayout<CFString>.size)
    try withUnsafeMutablePointer(to: &value) { pointer in
        try check(AudioObjectGetPropertyData(id, &address, 0, nil, &size, pointer), "Read device property")
    }
    return value as String
}

func outputDevices() throws -> [Device] {
    var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    try check(AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size), "List devices")
    var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    try check(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids), "List devices")
    return try ids.compactMap { id in
        var output = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        var streamSize: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(id, &output, 0, nil, &streamSize), "Read output streams")
        guard streamSize > 0 else { return nil }
        return Device(uid: try stringProperty(id, kAudioDevicePropertyDeviceUID), name: try stringProperty(id, kAudioObjectPropertyName))
    }
}

final class PlaybackState {
    let condition = NSCondition()
    var consumed = false
    func markConsumed() {
        condition.lock()
        consumed = true
        condition.broadcast()
        condition.unlock()
    }
    func waitUntilConsumed(deadline: Date) throws {
        condition.lock()
        defer { condition.unlock() }
        while !consumed {
            guard condition.wait(until: deadline) || consumed else {
                throw AudioFailure(message: "Audio buffer consumption timed out")
            }
        }
    }
}

func play(path: String, uid: String) throws {
    guard try outputDevices().contains(where: { $0.uid == uid }) else { throw AudioFailure(message: "Requested output UID is unavailable") }
    let wav = try Data(contentsOf: URL(fileURLWithPath: path))
    guard wav.count > 44, String(data: wav[0..<4], encoding: .ascii) == "RIFF", String(data: wav[8..<16], encoding: .ascii) == "WAVEfmt ", String(data: wav[36..<40], encoding: .ascii) == "data", (wav.count - 44) % 2 == 0 else { throw AudioFailure(message: "Invalid PCM WAV") }
    var format = AudioStreamBasicDescription(mSampleRate: 24000, mFormatID: kAudioFormatLinearPCM, mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked, mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2, mChannelsPerFrame: 1, mBitsPerChannel: 16, mReserved: 0)
    let state = PlaybackState()
    let context = Unmanaged.passUnretained(state).toOpaque()
    var queue: AudioQueueRef?
    try check(AudioQueueNewOutput(&format, { context, _, _ in
        guard let context else { return }
        Unmanaged<PlaybackState>.fromOpaque(context).takeUnretainedValue().markConsumed()
    }, context, nil, nil, 0, &queue), "Create audio queue")
    guard let queue else { throw AudioFailure(message: "Audio queue unavailable") }
    var disposed = false
    defer {
        if !disposed {
            let status = AudioQueueDispose(queue, true)
            if status != noErr {
                FileHandle.standardError.write(Data("Audio queue cleanup failed (\(status))\n".utf8))
            }
        }
    }
    var selected = uid as CFString
    try withUnsafePointer(to: &selected) { pointer in
        try check(AudioQueueSetProperty(queue, kAudioQueueProperty_CurrentDevice, pointer, UInt32(MemoryLayout<CFString>.size)), "Select exact output UID")
    }
    var actual: CFString = "" as CFString
    var actualSize = UInt32(MemoryLayout<CFString>.size)
    try withUnsafeMutablePointer(to: &actual) { pointer in
        try check(AudioQueueGetProperty(queue, kAudioQueueProperty_CurrentDevice, pointer, &actualSize), "Verify output UID")
    }
    guard actual as String == uid else { throw AudioFailure(message: "Audio queue selected a different output UID") }
    var buffer: AudioQueueBufferRef?
    try check(AudioQueueAllocateBuffer(queue, UInt32(wav.count - 44), &buffer), "Allocate audio buffer")
    guard let buffer else { throw AudioFailure(message: "Audio buffer unavailable") }
    wav.withUnsafeBytes { bytes in
        buffer.pointee.mAudioData.copyMemory(from: bytes.baseAddress!.advanced(by: 44), byteCount: wav.count - 44)
    }
    buffer.pointee.mAudioDataByteSize = UInt32(wav.count - 44)
    try check(AudioQueueEnqueueBuffer(queue, buffer, 0, nil), "Queue audio")
    let deadline = Date().addingTimeInterval(Double(wav.count - 44) / 48000 + 10)
    try check(AudioQueueStart(queue, nil), "Start audio")
    try state.waitUntilConsumed(deadline: deadline)
    try check(AudioQueueStop(queue, false), "Drain audio")
    while true {
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        try check(AudioQueueGetProperty(queue, kAudioQueueProperty_IsRunning, &running, &size), "Read playback status")
        if running == 0 { break }
        guard Date() < deadline else { throw AudioFailure(message: "Audio playback timed out") }
        Thread.sleep(forTimeInterval: 0.01)
    }
    disposed = true
    try check(AudioQueueDispose(queue, true), "Dispose audio queue")
}

do {
    let args = CommandLine.arguments
    if args.count == 2 && args[1] == "devices" {
        FileHandle.standardOutput.write(try JSONEncoder().encode(outputDevices()))
    } else if args.count == 4 && args[1] == "play" {
        try play(path: args[2], uid: args[3])
    } else { throw AudioFailure(message: "Expected devices or play WAV UID") }
} catch {
    let message = (error as? AudioFailure)?.message ?? "Native audio operation failed"
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}
