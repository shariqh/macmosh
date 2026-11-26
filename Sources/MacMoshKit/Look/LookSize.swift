import Foundation

/// The look's sizes in points (design 5.1, 5.2 and 6.5), and the opacities of a tile's shadow and ring.
public enum LookSize {
    /// A desk's tile, and its corners.
    public static let deskTile = 40.0
    public static let deskTileRadius = 10.0
    /// A sidebar tile, and its corners.
    public static let smallTile = 28.0
    public static let smallTileRadius = 8.0
    public static let buttonHeight = 28.0
    public static let buttonRadius = 8.0
    public static let panelRadius = 12.0
    /// A tile's shadow in light: 1 point down, 2 points of blur, black at 8 per cent.
    public static let shadowY = 1.0
    public static let shadowBlur = 2.0
    public static let shadowOpacity = 0.08
    /// A tile's ring in light: 1 point of black at 4 per cent. In dark the ring is the hairline colour.
    public static let ringOpacity = 0.04
    public static let ringWidth = 1.0
    /// A cell of a desk's tile, the gap between cells, and its corners.
    public static let cell = 6.0
    public static let cellGap = 3.0
    public static let cellRadius = 1.5
    public static let rowHeight = 52.0
    public static let sidebarWidth = 200.0
    /// The desk row's state cell: "In 2 tabs", "No tab", "Closed", "Updating…".
    public static let stateCellWidth = 92.0
    /// A desk's name is cut with "…" beyond this; it never wraps.
    public static let nameMaxWidth = 200.0
    /// The result slot's lines, always reserved. A count of lines, so a whole number.
    public static let resultLines = 2
    public static let titleFont = 22.0
    public static let bodyFont = 13.0
    public static let secondFont = 12.0
    public static let tagFont = 11.0
    /// A pressed button: black at 8 per cent over its fill, under its words.
    public static let pressedOverlay = 0.08
    /// A small button, inside a desk's opened details only.
    public static let smallButtonHeight = 24.0
    /// Around the workhorse page.
    public static let pagePadding = 20.0
    /// Inside the details panel and the greyed panel.
    public static let panelPadding = 12.0
    /// The details panel starts under the desk's tile: the chevron's 10 points and the row's 12-point gap.
    public static let detailsInset = 22.0
    /// Below about this much page width the facts in the details go under the window lines (design 6.6).
    public static let detailsStackBelowPageWidth = 620.0
    /// The same rule as the width the details' columns are offered: the page less its padding, the inset and the
    /// panel's padding. A scroll bar, when the system shows one, is not counted.
    public static var detailsStackBelowColumnsWidth: Double {
        detailsStackBelowPageWidth - 2 * pagePadding - detailsInset - 2 * panelPadding
    }
    /// Window names beside a desk's name are cut with "…" only while at least this many letters stay; below that they
    /// are left out. A count of letters, so a whole number.
    public static let windowNamesFewest = 4
}
