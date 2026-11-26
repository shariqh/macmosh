import Foundation

/// The icon's M (look design 8.1), drawn in the Add a Mac page's tile: 5 by 5 cells, row 0 at the top. Lit: column 0
/// and column 4 whole, row 1 column 1, row 1 column 3 and row 2 column 2, thirteen cells. Look step 5a's icon holds the
/// same cells; making them one table is a later step's.
public enum LetterM {
    public static let size = 5

    public static func isLit(row: Int, column: Int) -> Bool {
        guard (0..<size).contains(row), (0..<size).contains(column) else { return false }
        if column == 0 || column == size - 1 { return true }
        return (row == 1 && (column == 1 || column == 3)) || (row == 2 && column == 2)
    }
}
