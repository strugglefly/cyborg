//
//  Copyright © Uber Technologies, Inc. All rights reserved.
//

import Foundation

/// Contains either a `VectorDrawable`, or an `error` if the `VectorDrawable` could not be deserialized.
public enum Result {
    case ok(VectorDrawable)
    case error(ParseError)
}

/// An Error encountered when parsing. Generally optional, the presence of a value indicates that
/// an error occurred.
public typealias ParseError = String

// MARK: - Element Parsers

func assign<T>(_ string: XMLString,
                  to path: inout T,
                  creatingWith creator: (XMLString) -> (T?)) -> ParseError? {
    if let float = creator(string) {
        path = float
        return nil
    } else {
        return "Could not assign \(string)"
    }
}

func assignFloat(_ string: XMLString,
                 to path: inout CGFloat?) -> ParseError? {
    return assign(string, to: &path, creatingWith: { (string) in
        CGFloat(string)
    })
}

func assignFloat(_ string: XMLString,
                 to path: inout CGFloat) -> ParseError? {
    return assign(string, to: &path, creatingWith: { (string) in
        CGFloat(string)
    })
}

protocol NodeParsing: AnyObject {
    
    func parse(element: String, attributes: [(XMLString, XMLString)]) -> ParseError?
    
    func didEnd(element: String) -> Bool
}

class ParentParser<Child>: NodeParsing where Child: NodeParsing {
    
    var currentChild: Child?
    var children: [Child] = []
    var hasFoundElement = false
    let isArtificial: Bool
    
    init(isArtificial: Bool = false) {
        self.isArtificial = isArtificial
    }
    
    var name: Element {
        return .vector
    }
    
    func parse(element: String, attributes: [(XMLString, XMLString)]) -> ParseError? {
        if let currentChild = currentChild {
            return currentChild.parse(element: element, attributes: attributes)
        } else if element == name.rawValue,
            !hasFoundElement {
            hasFoundElement = true
            return parseAttributes(attributes)
        } else if let child = childForElement(element) {
            self.currentChild = child
            children.append(child)
            return child.parse(element: element, attributes: attributes)
        } else {
            if !hasFoundElement {
                return "Element \"\(element)\" found, expected \(name.rawValue)."
            } else {
                return "Found element \"\(element)\" nested, when it is not an acceptable child node."
            }
        }
    }
    
    func parseAttributes(_ attributes: [(XMLString, XMLString)]) -> ParseError? {
        return nil
    }
    
    func childForElement(_ element: String) -> Child? {
        return nil
    }
    
    func didEnd(element: String) -> Bool {
        if let child = currentChild,
            child.didEnd(element: element) {
            currentChild = nil
            return isArtificial
        } else {
            return element == name.rawValue
        }
    }
    
}

final class VectorParser: ParentParser<GroupParser> {
    
    var baseWidth: CGFloat?
    var baseHeight: CGFloat?
    var viewPortWidth: CGFloat?
    var viewPortHeight: CGFloat?
    var tintMode: BlendMode?
    var tintColor: Color?
    var autoMirrored: Bool = false
    var alpha: CGFloat = 1
    
    override func parseAttributes(_ attributes: [(XMLString, XMLString)]) -> ParseError? {
        for (key, value) in attributes {
            if let property = VectorProperty(rawValue: String(key)) {
                let result: ParseError?
                switch property {
                case .schema:
                    // TODO: fail if schema not found
                    result = nil
                case .height: result = assign(value, to: &baseHeight, creatingWith: parseAndroidMeasurement(from: ))
                case .width: result = assign(value, to: &baseWidth,  creatingWith: parseAndroidMeasurement(from: ))
                case .viewPortHeight: result = assignFloat(value, to: &viewPortHeight)
                case .viewPortWidth: result = assignFloat(value, to: &viewPortWidth)
                case .tint: result = assign(value, to: &tintColor, creatingWith: Color.init)
                case .tintMode:
                    if let blendMode = BlendMode(value) {
                        tintMode = blendMode
                        result = nil
                    } else {
                        result = "Could not assign \(value)"
                    }
                case .autoMirrored: result = assign(value, to: &autoMirrored, creatingWith: Bool.init)
                case .alpha: result = assignFloat(value, to: &alpha)
                }
                if result != nil {
                    return result
                }
            } else {
                return "Key \(key) is not a valid attribute of <vector>"
            }
        }
        return nil
    }
    
    override func childForElement(_ element: String) -> GroupParser? {
        switch Element(rawValue: element) {
            // The group parser already has all its elements filled out,
            // so it'll "fall through" directly to the path.
        // All we need to do is give it a name for it to complete.
        case .some(.path): return GroupParser(groupName: "anonymous", isArtificial: true)
        case .some(.group): return GroupParser()
        default: return nil
        }
    }
    
    func createElement() -> Result {
        if let baseWidth = baseWidth,
            let baseHeight = baseHeight,
            let viewPortWidth = viewPortWidth,
            let viewPortHeight = viewPortHeight {
            let groups = children.map { group in
                group.createElement()! // TODO: have a better way of propogating errors
            }
            return .ok(.init(baseWidth: baseWidth,
                             baseHeight: baseHeight,
                             viewPortWidth: viewPortWidth,
                             viewPortHeight: viewPortHeight,
                             baseAlpha: alpha,
                             groups: groups))
        } else {
            return .error("Could not parse a <vector> element, but there was no error. This is a bug in the VectorDrawable Library.")
        }
    }
    
    func parseAndroidMeasurement(from text: XMLString) -> CGFloat? {
        if case .ok(let number, let index) = number(from: text, at: 0),
            let _ = AndroidUnitOfMeasure(rawValue: String(text[index..<text.count])) {
            return number
        } else {
            return nil
        }
    }
    
}

final class PathParser: GroupChildParser {
    
    static let name: Element = .path
    
    var pathName: String?
    var commands: [PathSegment]?
    var fillColor: Color?
    var strokeColor: Color?
    var strokeWidth: CGFloat = 0
    var strokeAlpha: CGFloat = 1
    var fillAlpha: CGFloat = 1
    var trimPathStart: CGFloat = 0
    var trimPathEnd: CGFloat = 1
    var trimPathOffset: CGFloat = 0
    var strokeLineCap: LineCap = .butt
    var strokeMiterLimit: CGFloat = 4
    var strokeLineJoin: LineJoin = .miter
    var fillType: CGPathFillRule = .winding
    
    func parse(element: String, attributes: [(XMLString, XMLString)]) -> ParseError? {
        let baseError = "Error parsing the <android:pathData> tag: "
        for (key, value) in attributes {
            if let property = PathProperty(rawValue: String(key)) {
                let result: ParseError?
                switch property {
                case .name:
                    pathName = String(value)
                    result = nil
                case .pathData:
                    let subResult: ParseError?
                    let parsers = DrawingCommand
                        .all
                        .compactMap { (command) -> Parser<PathSegment>? in
                            command.parser()
                    }
                    switch consumeAll(using: parsers)(value, 0) {
                    case .ok(let result, _):
                        self.commands = result
                        subResult = nil
                    case .error(let error):
                        subResult = baseError + error
                    }
                    result = subResult
                case .fillColor:
                    fillColor = Color(value)! // TODO
                    result = nil // TODO
                case .strokeWidth:
                    result = assignFloat(value, to: &strokeWidth)
                case .strokeColor:
                    result = assign(value, to: &strokeColor, creatingWith: Color.init)
                case .strokeAlpha:
                    result = assignFloat(value, to: &strokeAlpha)
                case .fillAlpha:
                    result = assignFloat(value, to: &fillAlpha)
                case .trimPathStart:
                    result = assignFloat(value, to: &trimPathStart)
                case .trimPathEnd:
                    result = assignFloat(value, to: &trimPathEnd)
                case .trimPathOffset:
                    result = assignFloat(value, to: &trimPathOffset)
                case .strokeLineCap:
                    result = assign(value, to: &strokeLineCap, creatingWith: LineCap.init)
                case .strokeLineJoin:
                    result = assign(value, to: &strokeLineJoin, creatingWith: LineJoin.init)
                case .strokeMiterLimit:
                    result = assignFloat(value, to: &strokeMiterLimit)
                case .fillType:
                    result = assign(value, to: &fillType, creatingWith: { (string) -> (CGPathFillRule?) in
                        switch string {
                        case "evenOdd": return .evenOdd
                        case "nonZero": return .winding
                        default: return nil
                        }
                    })
                }
                if result != nil {
                    return result
                }
            } else {
                return "Key \(key) is not a valid attribute of <path>."
            }
        }
        return nil
    }
    
    func didEnd(element: String) -> Bool {
        return element == Element.path.rawValue
    }
    
    func createElement() -> GroupChild? {
        if let commands = commands {
            return VectorDrawable.Path(name: pathName,
                                       fillColor: fillColor,
                                       fillAlpha: fillAlpha,
                                       data: commands,
                                       strokeColor: strokeColor,
                                       strokeWidth: strokeWidth,
                                       strokeAlpha: strokeAlpha,
                                       trimPathStart: trimPathStart,
                                       trimPathEnd: trimPathEnd,
                                       trimPathOffset: trimPathOffset,
                                       strokeLineCap: strokeLineCap,
                                       strokeLineJoin: strokeLineJoin,
                                       fillType: fillType)
        } else {
            return nil
        }
    }
    
}

protocol GroupChildParser: NodeParsing {
    
    func createElement() -> GroupChild?
    
}

/// Necessary because we can't use a protocol to satisfy a generic with
/// type bounds, as that would make it impossible to dispatch static functions.
final class AnyGroupParserChild: GroupChildParser {
    
    let parser: GroupChildParser
    
    init(erasing parser: GroupChildParser) {
        self.parser = parser
    }
    
    func parse(element: String, attributes: [(XMLString, XMLString)]) -> ParseError? {
        return parser.parse(element: element, attributes: attributes)
    }
    
    func didEnd(element: String) -> Bool {
        return parser.didEnd(element: element)
    }
    
    func createElement() -> GroupChild? {
        return parser.createElement()
    }
    
}

final class GroupParser: ParentParser<AnyGroupParserChild>, GroupChildParser {
    
    override var name: Element {
        return .group
    }
    
    var groupName: String?
    var pivotX: CGFloat = 0
    var pivotY: CGFloat = 0
    var rotation: CGFloat = 0
    var scaleX: CGFloat = 1
    var scaleY: CGFloat = 1
    var translationX: CGFloat = 0
    var translationY: CGFloat = 0
    
    init(groupName: String? = nil, isArtificial: Bool = false) {
        self.groupName = groupName
        super.init(isArtificial: isArtificial)
    }
        
    override func parseAttributes(_ attributes: [(XMLString, XMLString)]) -> ParseError? {
        for (key, value) in attributes {
            if let property = GroupProperty(rawValue: String(key)) {
                let result: ParseError?
                switch property {
                case .name:
                    groupName = String(value)
                    result = nil
                case .rotation:
                    result = assignFloat(value, to: &rotation)
                case .pivotX:
                    result = assignFloat(value, to: &pivotX)
                case .pivotY:
                    result = assignFloat(value, to: &pivotY)
                case .scaleX:
                    result = assignFloat(value, to: &scaleX)
                case .scaleY:
                    result = assignFloat(value, to: &scaleY)
                case .translateX:
                    result = assignFloat(value, to: &translationX)
                case .translateY:
                    result = assignFloat(value, to: &translationY)
                }
                if result != nil {
                    return result
                }
            } else {
                return "Unrecognized Attribute: \(key)"
            }
        }
        return nil
    }
    
    func createElement() -> GroupChild? {
        let childElements = children.map { (parser) in
            parser.createElement()! // TODO
        }
        return VectorDrawable.Group(name: groupName,
                                    transform: Transform(pivot: .init(x: pivotX, y: pivotY),
                                                         rotation: rotation,
                                                         scale: .init(x: scaleX, y: scaleY),
                                                         translation: .init(x: translationX, y: translationY)),
                                    children: childElements)
    }
    
    override func childForElement(_ element: String) -> AnyGroupParserChild? {
        switch Element(rawValue: element) {
        case .some(.path): return AnyGroupParserChild(erasing: PathParser())
        case .some(.group): return AnyGroupParserChild(erasing: GroupParser())
        default: return nil
        }
    }
    
}

// MARK: - Parser Combinators

func consumeTrivia<T>(before: @escaping Parser<T>) -> Parser<T> {
    return { stream, index in
        var next = index
        while next != stream.count,
            stream[next] == 10 || stream[next] == 32 { // whitespace or newline
                // TODO: are these the the only whitespaces that are acceptable?
                // is there a more readable way to represent them?
            next += 1
        }
        return before(stream, next)
    }
}

func number(from stream: XMLString, at index: Int32) -> ParseResult<CGFloat> {
    let substring = stream[index..<stream.count]
    let pointer = substring.underlying
    return pointer.withMemoryRebound(to: Int8.self,
                                     capacity: Int(substring.count)) { (buffer) in
                                        var next: UnsafeMutablePointer<Int8>? = UnsafeMutablePointer(mutating: buffer)
                                        let result = strtod(buffer, &next)
                                        if result == 0.0,
                                            next == buffer {
                                            return ParseResult(error: "failed to make an int", index: index, stream: stream)
                                        } else if var final = next {
                                            if final.pointee == 44 { // comma
                                                final = final.advanced(by: 1)
                                            }
                                            let index = index + Int32(buffer.distance(to: final))
                                            return .ok(CGFloat(result), index)
                                        } else {
                                            return ParseResult(error: "failed to make an int", index: index, stream: stream)
                                        }
    }
}

fileprivate let whitespace = CharacterSet.whitespacesAndNewlines

fileprivate let digits = CharacterSet.decimalDigits

func numbers() -> Parser<[CGFloat]> {
    return { stream, index in
        var result = [CGFloat]()
        var nextIndex = index
        while case .ok(let value, let index) = number(from: stream, at: nextIndex) {
            result.append(value)
            nextIndex = index
        }
        if result.count > 0 {
            return .ok(result, nextIndex)
        } else {
            return .error("")
        }
    }
}

func seq<T, U>(_ first: @escaping Parser<T>,
                  _ second: @escaping Parser<U>) -> Parser<(T, U)> {
    return { stream, index in
        first(stream, index).map { result, index in
            second(stream, index).map { secondResult, index in
                .ok((result, secondResult), index)
            }
        }
    }
}


func seq<T, U, V>(_ first: @escaping Parser<T>,
                  _ second: @escaping Parser<U>,
                  _ third: @escaping Parser<V>) -> Parser<(T, U, V)> {
    return { stream, index in
        first(stream, index).map { result, index in
            second(stream, index).map { secondResult, index in
                third(stream, index).map { thirdResult, index in
                    .ok((result, secondResult, thirdResult), index)
                }
            }
        }
    }
}

func seq<T, U, V, W>(_ first: @escaping Parser<T>,
                     _ second: @escaping Parser<U>,
                     _ third: @escaping Parser<V>,
                     _ fourth: @escaping Parser<W>) -> Parser<(T, U, V, W)> {
    return { stream, index in
        first(stream, index).map { result, index in
            second(stream, index).map { secondResult, index in
                third(stream, index).map { thirdResult, index in
                    fourth(stream, index).map { fourthResult, index in
                        .ok((result, secondResult, thirdResult, fourthResult), index)
                    }
                }
            }
        }
    }
}

func coordinatePair() -> Parser<CGPoint> {
    return { stream, index in
        var point: CGPoint = .zero
        var next = index
        if case .ok(let found, let index) = number(from: stream, at: next) {
            point.x = CGFloat(found)
            next = index
        } else {
            return .error("")
        }
        if case .ok(let found, let index) = number(from: stream, at: next) {
            point.y = CGFloat(found)
            next = index
        } else {
            return .error("")
        }
        return .ok(point, next)
    }
}
