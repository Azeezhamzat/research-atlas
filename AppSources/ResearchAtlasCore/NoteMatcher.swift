import Foundation

public enum NoteMatcher {
    public static func suggestions(
        notes: [ObsidianNote],
        literature: [LiteratureItem],
        includeTitleMatches: Bool = false
    ) -> [PaperNoteLink] {
        var suggestions: [PaperNoteLink] = []
        for note in notes {
            let noteDOIs = Set(note.dois.map(normalizeDOI))
            let noteCitationKeys = Set(note.citationKeys.map(normalizeIdentifier))
            let content = note.content.lowercased()

            for item in literature where item.sourceAvailability == .available {
                if let doi = item.doi.map(normalizeDOI), !doi.isEmpty, noteDOIs.contains(doi) {
                    suggestions.append(PaperNoteLink(
                        noteID: note.id,
                        literatureID: item.id,
                        method: .doi,
                        matchedIdentifier: doi
                    ))
                    continue
                }
                if let citationKey = item.citationKey.map(normalizeIdentifier),
                   !citationKey.isEmpty,
                   noteCitationKeys.contains(citationKey) {
                    suggestions.append(PaperNoteLink(
                        noteID: note.id,
                        literatureID: item.id,
                        method: .citationKey,
                        matchedIdentifier: item.citationKey ?? citationKey
                    ))
                    continue
                }
                if let zoteroKey = item.zoteroKey?.lowercased(),
                   content.range(of: #"zotero://[^\s)\]]*/items/\#(zoteroKey)\b"#, options: .regularExpression) != nil {
                    suggestions.append(PaperNoteLink(
                        noteID: note.id,
                        literatureID: item.id,
                        method: .zoteroItemLink,
                        matchedIdentifier: item.zoteroKey ?? zoteroKey
                    ))
                    continue
                }
                if includeTitleMatches {
                    let noteTitle = normalizeTitle(note.title)
                    let paperTitle = normalizeTitle(item.title)
                    if noteTitle == paperTitle, paperTitle.count >= 8, paperTitle.split(separator: " ").count >= 2 {
                        suggestions.append(PaperNoteLink(
                            noteID: note.id,
                            literatureID: item.id,
                            method: .title,
                            matchedIdentifier: item.title
                        ))
                    }
                }
            }
        }
        return suggestions
    }

    private static func normalizeDOI(_ value: String) -> String {
        value.lowercased()
            .replacingOccurrences(of: "https://doi.org/", with: "")
            .replacingOccurrences(of: "http://doi.org/", with: "")
            .replacingOccurrences(of: "doi:", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizeIdentifier(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func normalizeTitle(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
