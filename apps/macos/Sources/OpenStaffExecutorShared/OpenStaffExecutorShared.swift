import Foundation

@objc public protocol OpenStaffExecutorXPCProtocol {
    func execute(_ request: NSDictionary, withReply reply: @escaping (NSDictionary) -> Void)
    func ping(_ reply: @escaping (NSString) -> Void)
}

public enum OpenStaffExecutorIPCKeys {
    public static let actionType = "actionType"
    public static let target = "target"
    public static let instruction = "instruction"
    public static let contextBundleId = "contextBundleId"
    public static let fallbackX = "fallbackX"
    public static let fallbackY = "fallbackY"

    public static let success = "success"
    public static let blocked = "blocked"
    public static let message = "message"
}
