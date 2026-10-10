import AppKit
import SwiftUI
import CoreImage

enum MarkTool: String, CaseIterable {
    case rectangle, ellipse, arrow, pen, text, mosaic
    var symbol: String {
        switch self {
        case .rectangle: "rectangle"
        case .ellipse: "circle"
        case .arrow: "arrow.up.right"
        case .pen: "pencil"
        case .text: "textformat"
        case .mosaic: "square.grid.3x3.fill"
        }
    }
    var title: String {
        switch self {
        case .rectangle: "矩形"
        case .ellipse: "圆圈"
        case .arrow: "箭头"
        case .pen: "画笔"
        case .text: "文字"
        case .mosaic: "马赛克"
        }
    }
}

struct ImageMark {
    var tool: MarkTool
    var points: [CGPoint]
    var color: Int
    // Fraction of the image's shorter side, identical in preview and export.
    var width: CGFloat
    var text = ""
}

@MainActor final class MarkSettings: ObservableObject {
    @Published var tool: MarkTool = .arrow
    @Published var color = 0
    @Published var thickness = 1
    static let colors: [NSColor] = [.systemRed, .systemYellow, .systemBlue,
                                  NSColor(calibratedWhite: 0.15, alpha: 1), .white]
}

@MainActor enum MarkRenderer {
    private static let pixelContext = CIContext()
    private static let pixelCache = NSCache<NSImage, NSImage>()
    static func fit(_ size: CGSize, in bounds: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0 else { return .zero }
        let scale = min(bounds.width / size.width, bounds.height / size.height)
        let s = CGSize(width: size.width * scale, height: size.height * scale)
        return CGRect(x: bounds.midX - s.width / 2, y: bounds.midY - s.height / 2, width: s.width, height: s.height)
    }
    static func draw(_ image: NSImage, marks: [ImageMark], in rect: CGRect) {
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: rect).addClip()
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        for mark in marks {
            guard let first = mark.points.first, let last = mark.points.last else { continue }
            func point(_ p: CGPoint) -> CGPoint { CGPoint(x: rect.minX+p.x*rect.width, y: rect.minY+p.y*rect.height) }
            let a = point(first), b = point(last)
            let box = CGRect(x: min(a.x,b.x), y: min(a.y,b.y), width: abs(a.x-b.x), height: abs(a.y-b.y))
            let width = max(1, mark.width * min(rect.width,rect.height))
            let color = MarkSettings.colors[min(max(mark.color,0),4)]
            color.setStroke(); color.setFill()
            let path = NSBezierPath(); path.lineWidth = width; path.lineCapStyle = .round; path.lineJoinStyle = .round
            switch mark.tool {
            case .rectangle: path.appendRect(box); path.stroke()
            case .ellipse: path.appendOval(in: box); path.stroke()
            case .pen:
                path.move(to: a); for p in mark.points.dropFirst() { path.line(to: point(p)) }; path.stroke()
            case .arrow:
                path.move(to:a); path.line(to:b); path.stroke()
                let angle = atan2(b.y-a.y,b.x-a.x), length = max(width*4, 8*rect.width/480)
                path.move(to: CGPoint(x:b.x-length*cos(angle-0.5),y:b.y-length*sin(angle-0.5)))
                path.line(to:b)
                path.line(to: CGPoint(x:b.x-length*cos(angle+0.5),y:b.y-length*sin(angle+0.5)))
                path.stroke()
            case .text:
                (mark.text as NSString).draw(at:a, withAttributes:[.font:NSFont.systemFont(ofSize:max(10,width*5),weight:.medium),.foregroundColor:color])
            case .mosaic:
                // Pixelate source pixels, clipped to the user-selected rectangle.
                guard box.width > 0, box.height > 0,
                      let cg = image.cgImage(forProposedRect:nil, context:nil, hints:nil) else { continue }
                if let cached = pixelCache.object(forKey:image) {
                    NSGraphicsContext.saveGraphicsState(); NSBezierPath(rect:box).addClip()
                    cached.draw(in:rect,from:.zero,operation:.sourceOver,fraction:1)
                    NSGraphicsContext.restoreGraphicsState(); continue
                }
                let ci = CIImage(cgImage:cg)
                let filter = ci.applyingFilter("CIPixellate", parameters:[kCIInputScaleKey:max(12,CGFloat(cg.width)*0.025)])
                if let result = pixelContext.createCGImage(filter, from:ci.extent) {
                    let pixelated = NSImage(cgImage:result,size:image.size)
                    pixelCache.countLimit = 8
                    pixelCache.setObject(pixelated, forKey:image)
                    NSGraphicsContext.saveGraphicsState(); NSBezierPath(rect:box).addClip()
                    pixelated.draw(in:rect,from:.zero,operation:.sourceOver,fraction:1)
                    NSGraphicsContext.restoreGraphicsState()
                }
            }
        }
        NSGraphicsContext.restoreGraphicsState()
    }
    static func export(url: URL, marks: [ImageMark]) -> NSImage? {
        guard let original = NSImage(contentsOf:url) else { return nil }
        guard !marks.isEmpty else { return original }
        guard let cg = original.cgImage(forProposedRect:nil,context:nil,hints:nil),
              let bitmap = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:cg.width,pixelsHigh:cg.height,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0),
              let context = NSGraphicsContext(bitmapImageRep:bitmap) else { return nil }
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
        draw(original,marks:marks,in:CGRect(x:0,y:0,width:cg.width,height:cg.height))
        NSGraphicsContext.restoreGraphicsState()
        let result=NSImage(size:NSSize(width:cg.width,height:cg.height)); result.addRepresentation(bitmap)
        return result
    }
}

struct MarkCanvas: NSViewRepresentable {
    let item: ScreenshotItem
    @ObservedObject var state: CaptureState
    @ObservedObject var settings: MarkSettings
    func makeNSView(context: Context) -> MarkCanvasView {
        let view=MarkCanvasView(); view.image=NSImage(contentsOf:item.fileURL); updateNSView(view,context:context); return view
    }
    func updateNSView(_ view: MarkCanvasView, context: Context) {
        view.marks=item.marks; view.tool=settings.tool; view.color=settings.color
        view.stroke=CGFloat(settings.thickness+1)*0.005
        view.enabled = !state.isBusy
        view.append={ state.addMark($0, for:item.id) }; view.needsDisplay=true
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: MarkCanvasView, context: Context) -> CGSize? {
        CGSize(width:proposal.width ?? 420,height:proposal.height ?? 350)
    }
}

final class MarkCanvasView: NSView, NSTextFieldDelegate {
    var image: NSImage?
    var marks: [ImageMark] = []
    var tool: MarkTool = .arrow
    var color=0
    var stroke: CGFloat=0.01
    var enabled=true
    var append: ((ImageMark)->Void)?
    private var draft: ImageMark?
    private var field: NSTextField?
    private static weak var activeTextCanvas: MarkCanvasView?
    static func commitActiveText() { activeTextCanvas?.finishText() }
    private var textMark: ImageMark?
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event:NSEvent?) -> Bool {true}
    override var intrinsicContentSize:NSSize { NSSize(width:NSView.noIntrinsicMetric,height:NSView.noIntrinsicMetric) }
    private var imageRect: CGRect { MarkRenderer.fit(image?.size ?? .zero,in:bounds) }
    private func normalized(_ event:NSEvent) -> CGPoint {
        let p=convert(event.locationInWindow,from:nil), r=imageRect
        return CGPoint(x:min(1,max(0,(p.x-r.minX)/max(1,r.width))),y:min(1,max(0,(p.y-r.minY)/max(1,r.height))))
    }
    override func draw(_ dirtyRect:NSRect) {
        guard let image else {return}
        MarkRenderer.draw(image,marks:marks + (draft.map{[$0]} ?? []),in:imageRect)
    }
    override func mouseDown(with event:NSEvent) {
        guard enabled, imageRect.contains(convert(event.locationInWindow,from:nil)) else {return}
        NoteEditor.commitCurrentInput(); finishText()
        let p=normalized(event)
        let mark=ImageMark(tool:tool,points:[p],color:color,width:stroke)
        if tool == .text {
            Self.activeTextCanvas=self
            textMark=mark
            let r=imageRect, location=convert(event.locationInWindow,from:nil)
            let input=NSTextField(frame:NSRect(x:min(location.x,r.maxX-100),y:max(r.minY,location.y-10),width:100,height:26))
            input.placeholderString="输入文字"; input.delegate=self; input.font = .systemFont(ofSize:14)
            addSubview(input); field=input; window?.makeFirstResponder(input)
        } else { window?.makeFirstResponder(self); draft=mark }
    }
    override func mouseDragged(with event:NSEvent) {
        guard draft != nil else {return}
        let p=normalized(event)
        if tool == .pen || draft!.points.count == 1 { draft!.points.append(p) }
        else {draft!.points[draft!.points.count-1]=p}
        needsDisplay=true
    }
    override func mouseUp(with event:NSEvent) {
        if let mark=draft, mark.points.count > 1 {append?(mark)}
        draft=nil; needsDisplay=true
    }
    func controlTextDidEndEditing(_ obj:Notification) { finishText() }
    private func finishText() {
        guard let input=field, var mark=textMark else {return}
        field=nil; textMark=nil
        if Self.activeTextCanvas === self { Self.activeTextCanvas=nil }
        mark.text=input.stringValue.trimmingCharacters(in:.whitespacesAndNewlines)
        input.removeFromSuperview()
        if !mark.text.isEmpty {append?(mark)}
    }
    override func keyDown(with event:NSEvent) {
        if event.keyCode == 53 {draft=nil; field?.removeFromSuperview(); field=nil; textMark=nil; needsDisplay=true}
        else {super.keyDown(with:event)}
    }
}

struct MarkTools: View {
    @ObservedObject var state: CaptureState
    let item: ScreenshotItem
    @ObservedObject var settings: MarkSettings
    var body: some View {
        VStack(alignment:.leading,spacing:10) {
            Divider()
            Text("图片标记").font(.system(size:12,weight:.medium))
            LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:6),count:4),spacing:6) {
                ForEach(MarkTool.allCases,id: \.self) { tool in
                    Button { settings.tool=tool } label: {
                        Group {
                            if tool == .text { Text("T").font(.system(size:16,weight:.medium)) }
                            else { Image(systemName:tool.symbol) }
                        }.frame(maxWidth:.infinity).frame(height:30)
                            .background(settings.tool == tool ? InterfaceStyle.accentBackground : InterfaceStyle.background,in:RoundedRectangle(cornerRadius:6))
                    }.buttonStyle(.plain).help(tool.title).accessibilityLabel(tool.title)
                }
                Button {state.undoMark(for:item.id)} label:{Image(systemName:"arrow.uturn.backward").frame(height:30)}
                    .buttonStyle(.plain).disabled(item.marks.isEmpty).help("撤销标记")
                Button {state.redoMark(for:item.id)} label:{Image(systemName:"arrow.uturn.forward").frame(height:30)}
                    .buttonStyle(.plain).disabled(item.redoMarks.isEmpty).help("重做标记")
            }
            HStack(spacing:13) {
                ForEach(0..<5) { index in
                    Button {settings.color=index} label: {
                        Circle().fill(Color(nsColor:MarkSettings.colors[index])).frame(width:17,height:17)
                            .overlay(Circle().stroke(InterfaceStyle.line))
                            .padding(3).overlay(Circle().stroke(settings.color == index ? InterfaceStyle.accent : .clear,lineWidth:1.5))
                    }.buttonStyle(.plain).accessibilityLabel(["红色","黄色","蓝色","深灰","白色"][index])
                }
            }
            HStack(spacing:6) {
                ForEach(0..<3) { index in
                    Button {settings.thickness=index} label: {
                        Capsule().frame(width:22,height:CGFloat(index+1)).frame(maxWidth:.infinity).frame(height:24)
                            .background(settings.thickness == index ? InterfaceStyle.accentBackground : InterfaceStyle.background,in:RoundedRectangle(cornerRadius:5))
                    }.buttonStyle(.plain).accessibilityLabel(["细线","中线","粗线"][index])
                }
            }
            Text("标记画在图片上，备注随图片粘贴").font(.system(size:9)).foregroundStyle(InterfaceStyle.muted)
        }.foregroundStyle(InterfaceStyle.primaryButton).disabled(state.isBusy)
    }
}
