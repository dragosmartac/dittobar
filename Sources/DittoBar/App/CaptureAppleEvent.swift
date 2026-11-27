import Carbon
import Foundation

/// Read an Apple event object from the process that was frontmost at capture time.
struct CaptureAppleEvent {
    let processID: pid_t

    func get(_ object: NSAppleEventDescriptor) throws -> NSAppleEventDescriptor {
        let event = NSAppleEventDescriptor(eventClass: AEEventClass(kAECoreSuite),
                                           eventID: AEEventID(kAEGetData),
                                           targetDescriptor: .init(processIdentifier: processID),
                                           returnID: AEReturnID(kAutoGenerateReturnID),
                                           transactionID: AETransactionID(kAnyTransactionID))
        event.setParam(object, forKeyword: AEKeyword(keyDirectObject))
        let reply = try event.sendEvent(options: [.waitForReply, .canInteract], timeout: 30)
        if let error = reply.paramDescriptor(forKeyword: AEKeyword(keyErrorNumber)), error.int32Value != 0 {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(error.int32Value))
        }
        guard let value = reply.paramDescriptor(forKeyword: AEKeyword(keyDirectObject)) else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(errAENoSuchObject))
        }
        return value
    }

    static func property(_ code: OSType, of container: NSAppleEventDescriptor = .null()) throws -> NSAppleEventDescriptor {
        try specifier(want: typeProperty, form: formPropertyID, key: .init(typeCode: code), container: container)
    }

    static func specifier(want: OSType, form: Int, key: NSAppleEventDescriptor,
                          container: NSAppleEventDescriptor) throws -> NSAppleEventDescriptor {
        let record = NSAppleEventDescriptor.record()
        record.setDescriptor(.init(typeCode: want), forKeyword: AEKeyword(keyAEDesiredClass))
        record.setDescriptor(.init(enumCode: OSType(form)), forKeyword: AEKeyword(keyAEKeyForm))
        record.setDescriptor(key, forKeyword: AEKeyword(keyAEKeyData))
        record.setDescriptor(container, forKeyword: AEKeyword(keyAEContainer))
        guard let object = record.coerce(toDescriptorType: DescType(typeObjectSpecifier)) else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(errAECoercionFail))
        }
        return object
    }
}
