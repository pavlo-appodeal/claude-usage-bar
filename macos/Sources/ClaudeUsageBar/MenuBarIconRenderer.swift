import AppKit

private let labelWidth: CGFloat = 14
private let barWidth: CGFloat = 24
private let barHeight: CGFloat = 5
private let rowGap: CGFloat = 3
private let labelGap: CGFloat = 2
private let cornerRadius: CGFloat = 2
private let logoSize: CGFloat = 12
private let logoGap: CGFloat = 2
private let barsWidth: CGFloat = labelWidth + labelGap + barWidth + 2
private let iconWidth: CGFloat = logoSize + logoGap + barsWidth
private let iconHeight: CGFloat = 18
private let fontSize: CGFloat = 8

private struct CachedLabel {
    let string: NSAttributedString
    let size: NSSize
}

private let labelFont = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .medium)
private let labelAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .medium),
    .foregroundColor: NSColor.black
]

private let cachedLabels: [String: CachedLabel] = {
    let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .medium)
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
    var result = [String: CachedLabel]()
    for label in ["5h", "7d"] {
        let str = NSAttributedString(string: label, attributes: attrs)
        result[label] = CachedLabel(string: str, size: str.size())
    }
    return result
}()

private func drawRow(label: String, barX: CGFloat, barY: CGFloat, labelX: CGFloat, drawBarFill: (CGFloat, CGFloat) -> Void) {
    if let cached = cachedLabels[label] {
        let labelY = barY + (barHeight - cached.size.height) / 2
        cached.string.draw(at: NSPoint(x: labelX + labelWidth - cached.size.width, y: labelY))
    }
    drawBarFill(barX, barY)
}

func renderIcon(pct5h: Double, pct7d: Double) -> NSImage {
    let image = NSImage(size: NSSize(width: iconWidth, height: iconHeight), flipped: true) { _ in
        let offset = logoSize + logoGap
        let barX = offset + labelWidth + labelGap
        let topY = (iconHeight - barHeight * 2 - rowGap) / 2
        let bottomY = topY + barHeight + rowGap

        drawClaudeLogo(x: 0, y: (iconHeight - logoSize) / 2, size: logoSize)

        drawRow(label: "5h", barX: barX, barY: topY, labelX: offset) { x, y in
            drawBar(x: x, y: y, width: barWidth, height: barHeight, cornerRadius: cornerRadius, pct: pct5h)
        }
        drawRow(label: "7d", barX: barX, barY: bottomY, labelX: offset) { x, y in
            drawBar(x: x, y: y, width: barWidth, height: barHeight, cornerRadius: cornerRadius, pct: pct7d)
        }
        return true
    }
    image.isTemplate = true
    return image
}

func renderExtraUsageIcon(pct: Double, label: String, paceStatus: PaceStatus) -> NSImage {
    let textBarGap: CGFloat = 2
    let extraBarHeight: CGFloat = 4
    let minContentWidth: CGFloat = labelWidth + labelGap + barWidth

    let adaptiveAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .medium),
        .foregroundColor: NSColor.labelColor
    ]
    let labelStr = NSAttributedString(string: label, attributes: adaptiveAttrs)
    let labelSize = labelStr.size()
    let contentWidth = max(ceil(labelSize.width), minContentWidth)
    let dynIconWidth = logoSize + logoGap + contentWidth + 2

    let totalContentHeight = ceil(labelSize.height) + textBarGap + extraBarHeight
    let topY = (iconHeight - totalContentHeight) / 2
    let barY = topY + ceil(labelSize.height) + textBarGap

    let fillColor: NSColor
    switch paceStatus {
    case .onTrack: fillColor = .systemGreen
    case .warning: fillColor = .systemYellow
    case .over:    fillColor = .systemRed
    }

    let image = NSImage(size: NSSize(width: dynIconWidth, height: iconHeight), flipped: true) { _ in
        let offset = logoSize + logoGap

        drawClaudeLogoAdaptive(x: 0, y: (iconHeight - logoSize) / 2, size: logoSize)

        let textX = offset + (contentWidth - labelSize.width) / 2
        labelStr.draw(at: NSPoint(x: textX, y: topY))

        drawColoredBar(x: offset, y: barY, width: contentWidth, height: extraBarHeight,
                       cornerRadius: cornerRadius, pct: pct, fillColor: fillColor)
        return true
    }
    image.isTemplate = false
    return image
}

func renderUnauthenticatedIcon() -> NSImage {
    let image = NSImage(size: NSSize(width: iconWidth, height: iconHeight), flipped: true) { _ in
        let offset = logoSize + logoGap
        let barX = offset + labelWidth + labelGap
        let topY = (iconHeight - barHeight * 2 - rowGap) / 2
        let bottomY = topY + barHeight + rowGap

        drawClaudeLogo(x: 0, y: (iconHeight - logoSize) / 2, size: logoSize)

        drawRow(label: "5h", barX: barX, barY: topY, labelX: offset) { x, y in
            drawDashedBar(x: x, y: y, width: barWidth, height: barHeight, cornerRadius: cornerRadius)
        }
        drawRow(label: "7d", barX: barX, barY: bottomY, labelX: offset) { x, y in
            drawDashedBar(x: x, y: y, width: barWidth, height: barHeight, cornerRadius: cornerRadius)
        }
        return true
    }
    image.isTemplate = true
    return image
}

// MARK: - Bar drawing

private func drawBar(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, cornerRadius: CGFloat, pct: Double) {
    let bgRect = NSRect(x: x, y: y, width: width, height: height)
    let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: cornerRadius, yRadius: cornerRadius)
    NSColor.black.withAlphaComponent(0.25).setFill()
    bgPath.fill()

    let clampedPct = max(0, min(1, pct))
    if clampedPct > 0 {
        let fillWidth = width * clampedPct
        let fillRect = NSRect(x: x, y: y, width: fillWidth, height: height)
        let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: cornerRadius, yRadius: cornerRadius)
        NSColor.black.setFill()
        fillPath.fill()
    }
}

private func drawColoredBar(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, cornerRadius: CGFloat, pct: Double, fillColor: NSColor) {
    let bgRect = NSRect(x: x, y: y, width: width, height: height)
    let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: cornerRadius, yRadius: cornerRadius)
    NSColor.labelColor.withAlphaComponent(0.2).setFill()
    bgPath.fill()

    let clampedPct = max(0, min(1, pct))
    if clampedPct > 0 {
        let fillRect = NSRect(x: x, y: y, width: width * clampedPct, height: height)
        let fillPath = NSBezierPath(roundedRect: fillRect, xRadius: cornerRadius, yRadius: cornerRadius)
        fillColor.setFill()
        fillPath.fill()
    }
}

private func drawDashedBar(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, cornerRadius: CGFloat) {
    let rect = NSRect(x: x, y: y, width: width, height: height)
    let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
    NSColor.black.withAlphaComponent(0.25).setStroke()
    path.lineWidth = 1
    let dashPattern: [CGFloat] = [2, 2]
    path.setLineDash(dashPattern, count: 2, phase: 0)
    path.stroke()
}

// MARK: - Claude logo (pre-rendered 512px template PNG)

private let claudeLogoImage: NSImage? = {
    if let bundle = claudeUsageBarResourceBundle(),
       let png = bundle.url(forResource: "claude-logo", withExtension: "png") {
        return NSImage(contentsOf: png)
    }
    return nil
}()

private func drawClaudeLogo(x: CGFloat, y: CGFloat, size: CGFloat) {
    guard let logo = claudeLogoImage else { return }
    logo.draw(in: NSRect(x: x, y: y, width: size, height: size))
}

private func drawClaudeLogoAdaptive(x: CGFloat, y: CGFloat, size: CGFloat) {
    guard let logo = claudeLogoImage else { return }
    let destRect = NSRect(x: x, y: y, width: size, height: size)
    // Tint the template logo with labelColor so it adapts to dark/light mode
    let tinted = NSImage(size: NSSize(width: size, height: size), flipped: true) { bounds in
        NSColor.labelColor.setFill()
        NSBezierPath(rect: bounds).fill()
        logo.draw(in: bounds, from: .zero, operation: .destinationIn, fraction: 1.0)
        return true
    }
    tinted.draw(in: destRect)
}
