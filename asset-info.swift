#!/usr/bin/env swift

/*
Example Mac asset info collection script

Gets the following properties:

Serial (IOKit)
UDID (IOKit)
Model (IOKit)
Description (HTTP request)
CPU (Darwin.sysctl)
Memory (Darwin.sysctl)
OS (ProcessInfo)
Storage (IOKit)
WiFi MAC (IOKit)
Bluetooth MAC (IOKit)
Ethernet MAC (IOKit)
Battery Charge (IOKit)
*/

import Foundation
import IOKit

/*
Splits string into pairs of characters (useful for MAC addresses)
*/
extension String {
	var pairs: [String] {
		var result: [String] = []
		let characters = Array(self)
		stride(from: 0, to: characters.count, by: 2).forEach {
			result.append(String(characters[$0..<min($0+2, characters.count)]))
		}
		return result
	}
}

/*
Returns a dictionary of properties for a given IOService
*/
func ioServiceDicts(ioService: String) -> [NSDictionary] {
	var serviceDicts = [NSDictionary]()
	var iter: io_iterator_t = 0
	IOServiceGetMatchingServices(kIOMasterPortDefault, IOServiceMatching(ioService), &iter)
	while true {
		let service: io_service_t = IOIteratorNext(iter)
		if service == 0 {
			break
		}
		var cfProps: Unmanaged<CFMutableDictionary>?
		if IORegistryEntryCreateCFProperties(service, &cfProps, kCFAllocatorDefault, 0) == KERN_SUCCESS {
			if let cfProps = cfProps {
				let serviceDict = cfProps.takeRetainedValue() as NSDictionary
				serviceDicts.append(serviceDict)
			}
		}
		IOObjectRelease(service)
	}
	IOObjectRelease(iter)
	return serviceDicts
}

/*
A "static"-only namespace around a series of functions that operate on buffers returned from the `Darwin.sysctl` function
Adapted from https://github.com/mattgallagher/CwlUtils/blob/master/Sources/CwlUtils/CwlSysctl.swift

Created by Matt Gallagher on 2016/02/03.
Copyright © 2016 Matt Gallagher ( http://cocoawithlove.com ). All rights reserved.

Permission to use, copy, modify, and/or distribute this software for any purpose with or without fee is hereby granted, provided that the above copyright notice and this permission notice appear in all copies.
*/
public struct Sysctl {
	/// Possible errors.
	public enum Error: Swift.Error {
		case unknown
		case malformedUTF8
		case invalidSize
		case posixError(POSIXErrorCode)
	}
	
	/// Access the raw data for an array of sysctl identifiers.
	public static func dataForKeys(_ keys: [Int32]) throws -> [Int8] {
		return try keys.withUnsafeBufferPointer() { keysPointer throws -> [Int8] in
			// Preflight the request to get the required data size
			var requiredSize = 0
			let preFlightResult = Darwin.sysctl(UnsafeMutablePointer<Int32>(mutating: keysPointer.baseAddress), UInt32(keys.count), nil, &requiredSize, nil, 0)
			if preFlightResult != 0 {
				throw POSIXErrorCode(rawValue: errno).map { Error.posixError($0) } ?? Error.unknown
			}
			
			// Run the actual request with an appropriately sized array buffer
			let data = Array<Int8>(repeating: 0, count: requiredSize)
			let result = data.withUnsafeBufferPointer() { dataBuffer -> Int32 in
				return Darwin.sysctl(UnsafeMutablePointer<Int32>(mutating: keysPointer.baseAddress), UInt32(keys.count), UnsafeMutableRawPointer(mutating: dataBuffer.baseAddress), &requiredSize, nil, 0)
			}
			if result != 0 {
				throw POSIXErrorCode(rawValue: errno).map { Error.posixError($0) } ?? Error.unknown
			}
			
			return data
		}
	}

	/// Convert a sysctl name string like "hw.memsize" to the array of `sysctl` identifiers (e.g. [CTL_HW, HW_MEMSIZE])
	public static func keysForName(_ name: String) throws -> [Int32] {
		var keysBufferSize = Int(CTL_MAXNAME)
		var keysBuffer = Array<Int32>(repeating: 0, count: keysBufferSize)
		try keysBuffer.withUnsafeMutableBufferPointer { (lbp: inout UnsafeMutableBufferPointer<Int32>) throws in
			try name.withCString { (nbp: UnsafePointer<Int8>) throws in
				guard sysctlnametomib(nbp, lbp.baseAddress, &keysBufferSize) == 0 else {
					throw POSIXErrorCode(rawValue: errno).map { Error.posixError($0) } ?? Error.unknown
				}
			}
		}
		if keysBuffer.count > keysBufferSize {
			keysBuffer.removeSubrange(keysBufferSize..<keysBuffer.count)
		}
		return keysBuffer
	}

	/// Invoke `sysctl` with an array of identifers, interpreting the returned buffer as the specified type. This function will throw `Error.invalidSize` if the size of buffer returned from `sysctl` fails to match the size of `T`.
	public static func valueOfType<T>(_ type: T.Type, forKeys keys: [Int32]) throws -> T {
		let buffer = try dataForKeys(keys)
		if buffer.count != MemoryLayout<T>.size {
			throw Error.invalidSize
		}
		return try buffer.withUnsafeBufferPointer() { bufferPtr throws -> T in
			guard let baseAddress = bufferPtr.baseAddress else { throw Error.unknown }
			return baseAddress.withMemoryRebound(to: T.self, capacity: 1) { $0.pointee }
		}
	}
	
	/// Invoke `sysctl` with an array of identifers, interpreting the returned buffer as the specified type. This function will throw `Error.invalidSize` if the size of buffer returned from `sysctl` fails to match the size of `T`.
	public static func valueOfType<T>(_ type: T.Type, forKeys keys: Int32...) throws -> T {
		return try valueOfType(type, forKeys: keys)
	}
	
	/// Invoke `sysctl` with the specified name, interpreting the returned buffer as the specified type. This function will throw `Error.invalidSize` if the size of buffer returned from `sysctl` fails to match the size of `T`.
	public static func valueOfType<T>(_ type: T.Type, forName name: String) throws -> T {
		return try valueOfType(type, forKeys: keysForName(name))
	}
	
	/// Invoke `sysctl` with an array of identifers, interpreting the returned buffer as a `String`. This function will throw `Error.malformedUTF8` if the buffer returned from `sysctl` cannot be interpreted as a UTF8 buffer.
	public static func stringForKeys(_ keys: [Int32]) throws -> String {
		let optionalString = try dataForKeys(keys).withUnsafeBufferPointer() { dataPointer -> String? in
			dataPointer.baseAddress.flatMap { String(validatingUTF8: $0) }
		}
		guard let s = optionalString else {
			throw Error.malformedUTF8
		}
		return s
	}
	
	/// Invoke `sysctl` with an array of identifers, interpreting the returned buffer as a `String`. This function will throw `Error.malformedUTF8` if the buffer returned from `sysctl` cannot be interpreted as a UTF8 buffer.
	public static func stringForKeys(_ keys: Int32...) throws -> String {
		return try stringForKeys(keys)
	}
	
	/// Invoke `sysctl` with the specified name, interpreting the returned buffer as a `String`. This function will throw `Error.malformedUTF8` if the buffer returned from `sysctl` cannot be interpreted as a UTF8 buffer.
	public static func stringForName(_ name: String) throws -> String {
		return try stringForKeys(keysForName(name))
	}
}

/*
Print the serial
*/
var serial = String()
let allPlatformProps = ioServiceDicts(ioService: "IOPlatformExpertDevice")
if allPlatformProps.count > 0 {
	let platformProps = allPlatformProps[0]
	if let value = platformProps["IOPlatformSerialNumber"] as? String {
		serial = value
		print("Serial: \(serial)")
	}
}

/*
Print the UDID
*/
if allPlatformProps.count > 0 {
	let platformProps = allPlatformProps[0]
	if let value = platformProps["IOPlatformUUID"] as? String {
		print("UDID: \(value)")
	}
}

/*
Print the model
*/
if allPlatformProps.count > 0 {
	let platformProps = allPlatformProps[0]
	if let value = platformProps["model"] as? Data {
		if let model = String(data: value, encoding: .utf8) {
			print("Model: \(model)")
		}
	}
}

/*
Print the model description
*/
let serialArray = Array(serial)
let serialLastFour = String(serialArray.suffix(from: serialArray.count - 4))
var urlString = "http://support-sp.apple.com/sp/product?"
let urlParams = [
	"cc=\(serialLastFour)",
	"lang=en_US"
]
if let urlEncodedParams = urlParams.joined(separator: "&").addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) {
	urlString += urlEncodedParams
}
if let url = URL(string: urlString) {
	let request = URLRequest(url: url)
	let semaphore = DispatchSemaphore(value: 0)
	URLSession.shared.dataTask(with: request) { (data, response, error) -> Void in
		if let data = data {
			if let dataString = String(data: data, encoding: String.Encoding.utf8) {
				if !dataString.contains("error") {
					if let modelNameStart = dataString.components(separatedBy: "<configCode>").last {
						if let modelName = modelNameStart.components(separatedBy: "</configCode>").first {
							print("Description: \(modelName)")
						}
					}
				}
			}
		}
		semaphore.signal()
		}.resume()
	_ = semaphore.wait(timeout: .distantFuture)
}

/*
Print the CPU description
*/
if let cpu = try? Sysctl.stringForName("machdep.cpu.brand_string") {
	print("CPU: \(cpu)")
}

/*
Print the Memory size
*/
if let memoryBytes = try? Sysctl.valueOfType(UInt64.self, forName: "hw.memsize") {
	var memoryGb = Double(memoryBytes) / 1024 / 1024 / 1024
	memoryGb = round(10 * memoryGb) / 10
	let memory = String(describing: memoryGb) + " GB"
	print("Memory: \(memory)")
}

/*
Print the OS version
*/
var os = ProcessInfo.init().operatingSystemVersionString
os = os.replacingOccurrences(of: "Version ", with: "")
os = os.replacingOccurrences(of: "Build ", with: "")
print("OS: \(os)")

/*
Print the APFS or CoreStorage capacity
*/
var classesToTry = ["AppleAPFSMedia", "CoreStorageLogical"]
for classToTry in classesToTry {
	let allStorageProps = ioServiceDicts(ioService: classToTry)
	for storageProps in allStorageProps {
		if let value = storageProps["Size"] {
			let storageBytes = value as! Double
			var storageGb = storageBytes / 1000000000
			storageGb = round(10 * storageGb) / 10
			let storage = String(describing: storageGb) + " GB"
			print("Storage: \(storage)")
		}
	}
}

/*
Print the WiFi address
*/
classesToTry = ["AirPort_BrcmNIC", "AirPort_Brcm4360", "AppleBCMWLANCore"]
for classToTry in classesToTry {
	let allwifiProps = ioServiceDicts(ioService: classToTry)
	for wifiProps in allwifiProps {
		if let value = wifiProps["IOMACAddress"] {
			var wifiMac = String(describing: value)
			var charsToTrim = CharacterSet.init(charactersIn: "<>")
			charsToTrim.formUnion(CharacterSet.whitespacesAndNewlines)
			wifiMac = wifiMac.trimmingCharacters(in: charsToTrim)
			wifiMac = wifiMac.replacingOccurrences(of: " ", with: "")
			wifiMac = wifiMac.pairs.joined(separator: ":").uppercased()
			print("WiFi MAC: \(wifiMac)")
		}
	}
}

/*
Print the Bluetooth address
*/
var bluetoothMac = String()
let allBluetoothProps = ioServiceDicts(ioService: "AppleBroadcomBluetoothHostController")
for bluetoothProps in allBluetoothProps {
	if let value = bluetoothProps["BluetoothDeviceAddressData"] {
		var bluetoothMac = String(describing: value)
		var charsToTrim = CharacterSet.init(charactersIn: "<>")
		charsToTrim.formUnion(CharacterSet.whitespacesAndNewlines)
		bluetoothMac = bluetoothMac.trimmingCharacters(in: charsToTrim)
		bluetoothMac = bluetoothMac.replacingOccurrences(of: " ", with: "")
		bluetoothMac = bluetoothMac.pairs.joined(separator: ":").uppercased()
		print("Bluetooth MAC: \(bluetoothMac)")
	}
}

/*
Print the ethernet address
*/
classesToTry = ["BCM5701Enet", "AppleEthernetAquantiaAqtion"]
for classToTry in classesToTry {
	let allEthernetProps = ioServiceDicts(ioService: classToTry)
	for ethernetProps in allEthernetProps {
		if let value = ethernetProps["IOMACAddress"] {
			if let prodcutName = ethernetProps["Product Name"] as? String {
				if prodcutName == "Thunderbolt Ethernet" {
					// Skip any thunderbolt ethernet adapters
					break
				}
			}
			var ethernetMac = String(describing: value)
			var charsToTrim = CharacterSet.init(charactersIn: "<>")
			charsToTrim.formUnion(CharacterSet.whitespacesAndNewlines)
			ethernetMac = ethernetMac.trimmingCharacters(in: charsToTrim)
			ethernetMac = ethernetMac.replacingOccurrences(of: " ", with: "")
			ethernetMac = ethernetMac.pairs.joined(separator: ":").uppercased()
			print("Ethernet MAC: \(ethernetMac)")
		}
	}
}

/*
Print the battery charge
*/

let allBatteryProps = ioServiceDicts(ioService: "IOPMPowerSource")
if allBatteryProps.count > 0 {
	let batteryProps = allBatteryProps[0]
	if let value = batteryProps["BatteryInstalled"] {
		if value as! Bool == true {
			var currentCharge = Double()
			var maxCharge = Double()
			if let value = batteryProps["CurrentCapacity"] {
				currentCharge = value as! Double
			}
			if let value = batteryProps["MaxCapacity"] {
				maxCharge = value as! Double
			}
			let percentCharge = currentCharge/maxCharge
			let charge =  round( 1000 * percentCharge ) / 10
			print("Battery Charge: \(charge)%")
		}
	}
}
