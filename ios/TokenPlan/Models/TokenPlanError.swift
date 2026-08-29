import Foundation
import Security

enum TokenPlanError: LocalizedError {
    case invalidEndpoint
    case missingCredentials
    case missingProfileCredentials
    case invalidRecoveryKey
    case encryptionFailed
    case decryptionFailed
    case invalidProfiles
    case cloudEmpty
    case unauthorized
    case conflict
    case http(Int)
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint: "服务器必须是 HTTPS 根地址"
        case .missingCredentials: "请填写同步令牌和恢复密钥"
        case .missingProfileCredentials: "请填写当前套餐所需的凭据"
        case .invalidRecoveryKey: "恢复密钥格式无效"
        case .encryptionFailed: "无法加密本地套餐"
        case .decryptionFailed: "无法解密云端套餐，请检查恢复密钥"
        case .invalidProfiles: "套餐配置无效或包含重复 ID"
        case .cloudEmpty: "云端尚无配置，请先从已有设备上传"
        case .unauthorized: "同步令牌被服务器拒绝"
        case .conflict: "云端版本已变化，请先下载"
        case let .http(status): "云同步请求失败（HTTP \(status)）"
        case let .keychain(status): "Keychain 操作失败（\(status)）"
        }
    }
}
