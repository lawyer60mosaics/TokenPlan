import Foundation
import Security

enum TokenPlanError: LocalizedError {
    case invalidEndpoint
    case missingCredentials
    case missingProfileCredentials
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
        case .invalidEndpoint: "套餐查询地址必须是有效的 HTTPS 地址"
        case .missingCredentials: "请输入账号和至少 16 位密码"
        case .missingProfileCredentials: "请填写当前套餐所需的凭据"
        case .encryptionFailed: "无法加密本地套餐"
        case .decryptionFailed: "无法解密云端套餐，请检查账号和密码"
        case .invalidProfiles: "套餐配置无效或包含重复 ID"
        case .cloudEmpty: "云端尚无配置，请先从已有设备上传"
        case .unauthorized: "账号或密码被服务器拒绝"
        case .conflict: "云端版本已变化，请先下载"
        case let .http(status): "云同步请求失败（HTTP \(status)）"
        case let .keychain(status): "Keychain 操作失败（\(status)）"
        }
    }
}
