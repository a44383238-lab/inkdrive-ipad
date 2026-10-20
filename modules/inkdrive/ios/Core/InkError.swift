import Foundation

enum InkError: LocalizedError {
    case invalidPDF, locked, signed, corruptInk, invalidPage, lastPage, invalidName, outsideFolder
    case conflict, unavailable, readOnly, serialization, busy, canceled
    var errorDescription: String? {
        switch self {
        case .invalidPDF: return "PDF를 읽을 수 없어요. 원본은 변경하지 않았어요."
        case .locked: return "암호로 잠긴 PDF예요. 잠금을 해제한 파일을 선택해 주세요."
        case .signed: return "디지털 서명 보존을 보장할 수 없어 이 PDF는 편집할 수 없어요."
        case .corruptInk: return "저장된 필기 데이터를 읽지 못했어요. 원본 보호를 위해 편집을 중지했어요."
        case .invalidPage: return "페이지 위치가 올바르지 않아요."
        case .lastPage: return "마지막 한 페이지는 삭제할 수 없어요."
        case .invalidName: return "이름은 1~120자이며 파일 경로나 예약 이름을 포함할 수 없어요."
        case .outsideFolder: return "선택한 폴더 밖의 경로는 사용할 수 없어요."
        case .conflict: return "다른 기기에서 원본을 수정했어요. 덮어쓰지 않았어요. 외부 버전을 다시 열거나 현재 편집을 별도 위치에 보존해 주세요."
        case .unavailable: return "파일 접근 권한이 만료됐거나 파일이 이동됐어요. 다시 선택해 주세요."
        case .readOnly: return "이 PDF는 수정 권한이 없어요."
        case .serialization: return "PDF 저장 데이터를 만들지 못했어요. 편집 내용은 이 화면에 남아 있어요."
        case .busy: return "진행 중인 작업이 끝난 뒤 다시 시도해 주세요."
        case .canceled: return "선택을 취소했어요."
        }
    }
}

enum FileNames {
    static func checked(_ input: String) throws -> String {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let invalid = CharacterSet(charactersIn: "<>:\"/\\|?*").union(.controlCharacters)
        let reserved = "^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\\.|$)"
        guard !value.isEmpty, value.utf16.count <= 120, value != ".", value != "..",
              value.rangeOfCharacter(from: invalid) == nil, !value.hasSuffix("."),
              value.range(of: reserved, options: [.regularExpression, .caseInsensitive]) == nil
        else { throw InkError.invalidName }
        return value
    }
    static func child(_ relative: String, in root: URL) throws -> URL {
        if relative.isEmpty { return root }
        let components = relative.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        for component in components {
            guard try checked(component) == component else { throw InkError.outsideFolder }
        }
        let base = root.resolvingSymlinksInPath().standardizedFileURL
        let candidate = components.reduce(base) { $0.appendingPathComponent($1) }.resolvingSymlinksInPath().standardizedFileURL
        guard candidate.path.hasPrefix(base.path + "/") else { throw InkError.outsideFolder }
        return candidate
    }
}
