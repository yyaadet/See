import Foundation

// MARK: - C function declarations via @_silgen_name

@_silgen_name("cmark_gfm_core_extensions_ensure_registered")
func cmark_gfm_core_extensions_ensure_registered()

@_silgen_name("cmark_parser_new")
func cmark_parser_new(_ options: Int32) -> UnsafeMutableRawPointer

@_silgen_name("cmark_parser_free")
func cmark_parser_free(_ parser: UnsafeMutableRawPointer)

@_silgen_name("cmark_parser_feed")
func cmark_parser_feed(_ parser: UnsafeMutableRawPointer, _ content: UnsafePointer<Int8>, _ len: Int32)

@_silgen_name("cmark_parser_finish")
func cmark_parser_finish(_ parser: UnsafeMutableRawPointer, _ error: UnsafeMutablePointer<UnsafeMutablePointer<Int8>?>?) -> UnsafeMutableRawPointer?

@_silgen_name("cmark_node_free")
func cmark_node_free(_ node: UnsafeMutableRawPointer)

@_silgen_name("cmark_render_html")
func cmark_render_html(_ node: UnsafeMutableRawPointer, _ options: Int32, _ extensions: UnsafeMutableRawPointer?) -> UnsafeMutablePointer<Int8>

// MARK: - Constants

private let CMARK_OPT_DEFAULT: Int32 = 0

// MARK: - Markdown rendering

/// Render CommonMark/GFM markdown to NSAttributedString using cmark-gfm.
func markdownToNSAttributedString(_ markdown: String) -> NSAttributedString? {
    guard let cString = markdown.cString(using: .utf8) else {
        return nil
    }

    cmark_gfm_core_extensions_ensure_registered()

    let parser = cmark_parser_new(CMARK_OPT_DEFAULT)
    defer { cmark_parser_free(parser) }

    cmark_parser_feed(parser, cString, Int32(markdown.utf8.count))
    cmark_parser_feed(parser, "\n", 1)

    let root = cmark_parser_finish(parser, nil)
    guard let root else { return nil }
    defer { cmark_node_free(root) }

    let html = cmark_render_html(root, CMARK_OPT_DEFAULT, nil)
    defer { free(html) }

    let htmlString = String(cString: html)
    guard let data = htmlString.data(using: .utf8) else { return nil }

    let parsed = try? NSAttributedString(
        data: data,
        options: [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ],
        documentAttributes: nil
    )
    return parsed
}
