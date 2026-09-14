import Foundation
import CryptoKit
let key=Curve25519.Signing.PrivateKey()
let file=URL(fileURLWithPath:CommandLine.arguments[1])
try key.rawRepresentation.base64EncodedString().write(to:file,atomically:true,encoding:.utf8)
try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:file.path)
try key.publicKey.rawRepresentation.base64EncodedString().write(to:file.appendingPathExtension("pub"),atomically:true,encoding:.utf8)
