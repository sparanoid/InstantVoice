import Foundation

let instantVoiceRefineXPCServiceName = "com.sparanoid.InstantVoice.RefineXPC"
let instantVoiceRefineXPCErrorDomain = "com.sparanoid.InstantVoice.RefineXPC"

struct InstantVoiceRefinePrepareRequest: Codable, Sendable {
    let requestID: UUID
    let modelDirectoryPath: String
    let systemPrompt: String
}

struct InstantVoiceRefineEnhanceRequest: Codable, Sendable {
    let requestID: UUID
    let modelDirectoryPath: String
    let systemPrompt: String
    let transcript: String
}

struct InstantVoiceRefineEnhanceResponse: Codable, Sendable {
    let requestID: UUID
    let output: String
}

enum InstantVoiceRefineXPCErrorCode: Int {
    case invalidRequest = 1
    case inferenceFailed = 2
    case invalidResponse = 3
    case connectionFailed = 4
}

@objc protocol InstantVoiceRefineXPCProtocol {
    func prepare(
        _ requestData: NSData,
        withReply reply: @escaping (NSError?) -> Void
    )

    func enhance(
        _ requestData: NSData,
        withReply reply: @escaping (NSData?, NSError?) -> Void
    )

    func shutdown(withReply reply: @escaping () -> Void)
}

func makeInstantVoiceRefineXPCError(
    _ code: InstantVoiceRefineXPCErrorCode,
    description: String
) -> NSError {
    NSError(
        domain: instantVoiceRefineXPCErrorDomain,
        code: code.rawValue,
        userInfo: [NSLocalizedDescriptionKey: description]
    )
}
