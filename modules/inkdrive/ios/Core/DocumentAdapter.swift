import Foundation

struct DocumentAdapter: Codable {
    let kind: String
    let originalPath: String
    let originalSHA256: String
    let width: Double
    let height: Double
    var documentID: UUID?
    var pageIDs: [UUID]?

    func convert(_ page: PortableInkPage, index: Int) throws -> PortableInkPage {
        if kind == "pptx", let pageIDs, !pageIDs.contains(where: { $0.uuidString.lowercased() == page.id.lowercased() }) { return page }
        guard ["pptx", "html-snapshot"].contains(kind), width > 0, height > 0, width.isFinite, height.isFinite,
              width <= 1e9, height <= 1e9, page.rotation == 0 else { throw InkError.serialization }
        let bounds = page.bounds, sx = width / bounds.width, sy = height / bounds.height
        // PDF user-space -> canonical top-left EMU / fixed CSS pixels.
        func point(_ x: Double, _ y: Double) -> (Double, Double) { ((x - bounds.x) * sx, (bounds.y + bounds.height - y) * sy) }
        let strokes = page.strokes.map { input -> PortableInkStroke in
            let t = input.transform
            // D*T*D^-1, including nonzero crop origin.
            let ox = bounds.x, oy = bounds.y + bounds.height
            let transform = [t[0], -t[1]*sy/sx, -t[2]*sx/sy, t[3], sx*(t[0]*ox+t[2]*oy+t[4]-ox), sy*(oy-t[1]*ox-t[3]*oy-t[5])]
            let samples = input.samples.map { p -> PortableInkSample in
                let (x,y) = point(p.x,p.y)
                return PortableInkSample(x: x, y: y, width: p.width*sx, height: p.height*sy, pressure: p.pressure, opacity: p.opacity, timeMs: p.timeMs)
            }
            var output = PortableInkStroke(id: input.id, layerId: input.layerId, tool: input.tool, color: input.color, opacity: input.opacity, createdAt: input.createdAt, updatedAt: input.updatedAt, transform: transform, samples: samples)
            output.mask = input.mask?.map { command in
                var result = [command[0]]
                if command.count > 1 { for i in stride(from: 1, to: command.count, by: 2) { let (x,y) = point(command[i],command[i+1]); result += [x,y] } }
                return result
            }
            output.maskEvenOdd = input.maskEvenOdd; return output
        }
        return PortableInkPage(id: page.id, kind: kind,
            unit: kind == "pptx" ? "emu" : "css-px", bounds: PortableInkBounds(x: 0, y: 0, width: width, height: height), rotation: 0, strokes: strokes)
    }
}
