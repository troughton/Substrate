public final class CharacterSet {

    private let characters : Set<Character>
    private let isInverted : Bool

    public init(characters: Set<Character>) {
        self.characters = characters
        self.isInverted = false
    }

    public init(charactersIn string: String) {
        self.characters = Set(string)
        self.isInverted = false
    }

    init(inverting: CharacterSet) {
        self.characters = inverting.characters
        self.isInverted = !inverting.isInverted
    }

    public var inverted : CharacterSet {
        return CharacterSet(inverting: self)
    }

    public func contains(_ character: Character) -> Bool {
        return !isInverted == self.characters.contains(character)
    }

    public func contains(_ scalar: Unicode.Scalar) -> Bool {
        return self.contains(Character(scalar))
    }

    public static let newlines = CharacterSet(characters: ["\r\n", "\r", "\n"])
}

public final class Locale {

}