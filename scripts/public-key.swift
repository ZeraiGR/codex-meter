import Foundation
import CryptoKit
let input=FileHandle.standardInput.readDataToEndOfFile()
guard let text=String(data:input,encoding:.utf8),let data=Data(base64Encoded:text.trimmingCharacters(in:.whitespacesAndNewlines)) else {fatalError("Invalid signing key encoding")}
let key=try Curve25519.Signing.PrivateKey(rawRepresentation:data)
print(key.publicKey.rawRepresentation.base64EncodedString())
