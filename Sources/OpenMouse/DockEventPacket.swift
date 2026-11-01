// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Open Mouse contributors.
// Swift adaptation of FasterSwiper's CGEventData/IOHID serialization, modified
// for Open Mouse. Source: mgbowen/FasterSwiper, commit
// 3665350bbd05cb7245063ade5143f155d8228d27, src/gesture-serialization.cc.
// See LICENSES/FasterSwiper-Apache-2.0.txt and THIRD_PARTY_NOTICES.md.

import Foundation
import CoreGraphics
import Darwin

/// A DockControl CGEvent can carry its native HID packet in serialized field
/// 4205. The outer CGEventData v2 is big-endian; the packed HID payload is
/// little-endian on supported Intel/Apple Silicon Macs. Unknown versions fail
/// without posting a malformed gesture.
enum DockEventPacket {
    static func augment(_ event: CGEvent, motion: Int64, phase: Int64, progress: Double, velocity: Double?) -> CGEvent? {
        guard progress.isFinite, velocity?.isFinite != false, let original = event.data else { return nil }
        let bytes = original as Data
        guard let records = records(in: bytes) else { return nil }
        let speed = velocity ?? 0
        let includeVelocity = phase == 4 || speed != 0
        var payload = Data()
        // IOHIDSystemQueueElement: timestamp, sender, options, attributes, count.
        appendLE(event.timestamp == 0 ? mach_absolute_time() : event.timestamp, width: 8, to: &payload)
        appendLE(0, width: 8, to: &payload)
        appendLE(0, width: 4, to: &payload)
        appendLE(0, width: 4, to: &payload)
        appendLE(includeVelocity ? 2 : 1, width: 4, to: &payload)
        // FluidTouchGesture: base16 + xyz12 + mask4 + motion2 + flavor2 + progress4.
        appendLE(40, width: 4, to: &payload)
        appendLE(23, width: 4, to: &payload)
        appendLE(UInt64(phase & 0xff) << 24, width: 4, to: &payload)
        appendLE(0, width: 4, to: &payload)
        appendLE(0, width: 4, to: &payload)
        appendLE(0, width: 4, to: &payload)
        appendLE(0, width: 4, to: &payload)
        appendLE(UInt64(bitPattern: event.getIntegerValueField(CGEventField(rawValue: 115)!)), width: 4, to: &payload)
        appendLE(UInt64(motion), width: 2, to: &payload)
        appendLE(3, width: 2, to: &payload) // DockPrimary flavor.
        appendLE(UInt64(UInt32(bitPattern: fixed(progress))), width: 4, to: &payload)
        if includeVelocity {
            appendLE(28, width: 4, to: &payload)
            appendLE(9, width: 4, to: &payload)
            appendLE(0, width: 4, to: &payload)
            appendLE(1, width: 4, to: &payload) // Child depth=1, three reserved bytes.
            appendLE(UInt64(UInt32(bitPattern: fixed(speed))), width: 4, to: &payload)
            appendLE(UInt64(UInt32(bitPattern: fixed(speed))), width: 4, to: &payload)
            appendLE(0, width: 4, to: &payload)
        }
        guard payload.count == (includeVelocity ? 96 : 68) else { return nil }
        var result = Data(bytes.prefix(4))
        for record in records where record.field != 4205 { result.append(bytes[record.range]) }
        appendBE(UInt16(payload.count), to: &result)
        appendBE(4205, to: &result) // tag=00, field=0x106d.
        result.append(payload)
        return CGEvent(withDataAllocator: nil, data: result as CFData)
    }

    static func payload(in event: CGEvent) -> Data? {
        guard let original = event.data else { return nil }
        let bytes = original as Data
        guard let record = records(in: bytes)?.first(where: { $0.field == 4205 }) else { return nil }
        return Data(bytes[(record.range.lowerBound + 4)..<record.range.upperBound])
    }

    private struct Record { let field: UInt16; let range: Range<Int> }
    private static func records(in data: Data) -> [Record]? {
        guard data.count >= 4, data.count <= 1_000_000, Array(data.prefix(4)) == [0, 0, 0, 2] else { return nil }
        var offset = 4, result: [Record] = []
        while offset < data.count {
            let start = offset
            guard offset + 4 <= data.count else { return nil }
            let count = UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
            let tagged = UInt16(data[offset + 2]) << 8 | UInt16(data[offset + 3])
            let tag = tagged >> 14
            let length: Int
            switch tag {
            case 0: guard count > 0 else { return nil }; length = count == 1 ? 8 : Int(count)
            case 1: guard count == 1 else { return nil }; length = 4
            case 3: guard count == 1 || count == 2 else { return nil }; length = Int(count) * 4
            default: return nil
            }
            offset += 4 + length
            guard offset <= data.count else { return nil }
            result.append(Record(field: tagged & 0x3fff, range: start..<offset))
        }
        return result
    }
    private static func fixed(_ value: Double) -> Int32 {
        let scaled = value * 65536
        return Int32(max(Double(Int32.min), min(Double(Int32.max), scaled)))
    }
    private static func appendLE(_ value: UInt64, width: Int, to data: inout Data) {
        for index in 0..<width { data.append(UInt8(truncatingIfNeeded: value >> (index * 8))) }
    }
    private static func appendBE(_ value: UInt16, to data: inout Data) {
        data.append(UInt8(truncatingIfNeeded: value >> 8)); data.append(UInt8(truncatingIfNeeded: value))
    }
}
