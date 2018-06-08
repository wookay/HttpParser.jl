using HttpParser
using HttpCommon
using Compat
using Compat.Test

FIREFOX_REQ = tuple("GET /favicon.ico HTTP/1.1\r\n",
         "Host: 0.0.0.0=5000\r\n",
         "User-Agent: Mozilla/5.0 (X11; U; Linux i686; en-US; rv:1.9) Gecko/2008061015 Firefox/3.0\r\n",
         "Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8\r\n",
         "Accept-Language: en-us,en;q=0.5\r\n",
         "Accept-Encoding: gzip,deflate\r\n",
         "Accept-Charset: ISO-8859-1,utf-8;q=0.7,*;q=0.7\r\n",
         "Keep-Alive: 300\r\n",
         "Connection: keep-alive\r\n",
         "\r\n")

MALFORMED = tuple("GET /MALFORMED HTTP/1.1\r\n",
         "aaaaaaaaaaaaa:++++++++++\r\n",
         "\r\n")

TWO_CHUNKS_MULT_ZERO_END = tuple("POST /two_chunks_mult_zero_end HTTP/1.1\r\n",
         "Transfer-Encoding: chunked\r\n",
         "\r\n",
         "5\r\nhello\r\n",
         "6\r\n world\r\n",
         "000\r\n",
         "\r\n")

WEBSOCK = tuple("DELETE /chat HTTP/1.1\r\n",
        "Host: server.example.com\r\n",
        "Upgrade: websocket\r\n",
        "Connection: Upgrade\r\n",
        "Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n",
        "Origin: http://example.com\r\n",
        "Sec-WebSocket-Protocol: chat, superchat\r\n",
        "Sec-WebSocket-Version: 13\r\n",
        "\r\n",)

r = Request("", "", Dict{AbstractString,AbstractString}(), "")

function on_message_begin(parser)
    # Clear the resource when the message starts
    r.resource = ""
    return 0
end

function on_url(parser, at, len)
    # Concatenate the resource for each on_url callback
    r.resource = string(r.resource, unsafe_string(convert(Ptr{UInt8}, at), Int(len)))
    return 0
end

function on_status_complete(parser)
    return 0
end

function on_header_field(parser, at, len)
    header = unsafe_string(convert(Ptr{UInt8}, at), Int(len))
    # set the current header
    r.headers["current_header"] = header
    return 0
end

function on_header_value(parser, at, len)
    s = unsafe_string(convert(Ptr{UInt8}, at), Int(len))
    # once we know we have the header value, that will be the value for current header
    r.headers[r.headers["current_header"]] = s
    # reset current_header
    r.headers["current_header"] = ""
    return 0
end

function on_headers_complete(parser)
    p = unsafe_load(parser)
    # get first two bits of p.type_and_flags

    # The parser type are the bottom two bits
    # 0x03 = 00000011
    ptype = p.type_and_flags & 0x03
    # flags = p.type_and_flags >>> 3
    if ptype == 0
        r.method = http_method_str(convert(Int, p.method))
    end
    if ptype == 1
        r.headers["status_code"] = string(convert(Int, p.status_code))
    end
    r.headers["http_major"] = string(convert(Int, p.http_major))
    r.headers["http_minor"] = string(convert(Int, p.http_minor))
    r.headers["Keep-Alive"] = string(http_should_keep_alive(parser))
    return 0
end

function on_body(parser, at, len)
    append!(r.data, unsafe_wrap(Array, convert(Ptr{UInt8}, at), (len,)))
    return 0
end

function on_message_complete(parser)
    return 0
end

function on_chunk_header(parser)
    return 0
end

function on_chunk_complete(parser)
    return 0
end

(cb_return,   cb_args)   = HttpParser.HTTP_CB
(data_return, data_args) = HttpParser.HTTP_DATA_CB
c_message_begin_cb    = Compat.@cfunction on_message_begin    cb_return   (cb_args...,)
c_url_cb              = Compat.@cfunction on_url              data_return (data_args...,)
c_status_complete_cb  = Compat.@cfunction on_status_complete  cb_return   (cb_args...,)
c_header_field_cb     = Compat.@cfunction on_header_field     data_return (data_args...,)
c_header_value_cb     = Compat.@cfunction on_header_value     data_return (data_args...,)
c_headers_complete_cb = Compat.@cfunction on_headers_complete cb_return   (cb_args...,)
c_body_cb             = Compat.@cfunction on_body             data_return (data_args...,)
c_message_complete_cb = Compat.@cfunction on_message_complete cb_return   (cb_args...,)
c_chunk_header_cb     = Compat.@cfunction on_chunk_header     cb_return   (cb_args...,)
c_chunk_complete_cb   = Compat.@cfunction on_chunk_complete   cb_return   (cb_args...,)

function init(test::Tuple)
    # reset request
    # Moved this up for testing purposes
    r.method = ""
    r.resource = ""
    r.headers = Dict{AbstractString, AbstractString}()
    r.data = Vector{UInt8}()
    parser = Parser()
    http_parser_init(parser)
    settings = ParserSettings(c_message_begin_cb, c_url_cb,
                              c_status_complete_cb, c_header_field_cb,
                              c_header_value_cb, c_headers_complete_cb,
                              c_body_cb, c_message_complete_cb,
                              c_chunk_header_cb, c_chunk_complete_cb)

    for i=1:length(test)
        size = http_parser_execute(parser, settings, test[i])
    end

    # errno = parser.errno_and_upgrade & 0xf3
    # upgrade = parser.errno_and_upgrade >>> 7
end

init(FIREFOX_REQ)
@test r.method == "GET"
@test r.resource == "/favicon.ico"
@test r.headers["Host"] == "0.0.0.0=5000"
@test r.headers["User-Agent"] == "Mozilla/5.0 (X11; U; Linux i686; en-US; rv:1.9) Gecko/2008061015 Firefox/3.0"
@test r.headers["Accept"] == "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
@test r.headers["Accept-Language"] == "en-us,en;q=0.5"
@test r.headers["Accept-Encoding"] == "gzip,deflate"
@test r.headers["Accept-Charset"] == "ISO-8859-1,utf-8;q=0.7,*;q=0.7"
@test r.headers["Keep-Alive"] == "1"
@test r.headers["Connection"] == "keep-alive"
@test isempty(r.data)
init(MALFORMED)
@test r.method == "GET"
@test r.resource == "/MALFORMED"
init(TWO_CHUNKS_MULT_ZERO_END)
@test r.method == "POST"
@test r.resource == "/two_chunks_mult_zero_end"
@test String(r.data) == "hello world"
# @test r.data == "hello\r\n5 world\r\n6"
init(WEBSOCK)
@test r.method == "DELETE"
@test r.resource == "/chat"

# URL Parser
const ParsedUrl = Dict{Symbol,AbstractString}

@test parse_url("//some_path") == (ParsedUrl(
    :UF_PATH=>"//some_path"
), 0)

@test parse_url("HTTP://www.example.com/") == (ParsedUrl(
    :UF_HOST=>"www.example.com",
    :UF_PATH=>"/",
    :UF_SCHEMA=>"HTTP"
), 0)

@test parse_url("HTTP://www.example.com") == (ParsedUrl(
    :UF_HOST=>"www.example.com",
    :UF_SCHEMA=>"HTTP"
), 0)

@test parse_url("http://user:aaa@www.example.com/") == (ParsedUrl(
    :UF_HOST=>"www.example.com",
    :UF_SCHEMA=>"http",
    :UF_USERINFO=>"user:aaa",
    :UF_PATH=>"/",
), 0)

@test parse_url("http://x.com/path?that%27s#all,%20folks") == (ParsedUrl(
    :UF_HOST=>"x.com",
    :UF_QUERY=>"that%27s",
    :UF_FRAGMENT=>"all,%20folks",
    :UF_SCHEMA=>"http",
    :UF_PATH=>"/path",
), 0)

@test parse_url("http://user:pass@example.com:8000/foo/bar?baz=quux#frag") == (ParsedUrl(
    :UF_PORT=>"8000",
    :UF_HOST=>"example.com",
    :UF_QUERY=>"baz=quux",
    :UF_FRAGMENT=>"frag",
    :UF_USERINFO=>"user:pass",
    :UF_PATH=>"/foo/bar",
    :UF_SCHEMA=>"http"
), 8000)

@test HttpParser.version() >= v"2.6"

p = Parser()
HttpParser.pause(p)
err = HttpParser.errno(p)
@test err == 0x1f
@test HttpParser.errno_name(err) == "HPE_PAUSED"
@test HttpParser.errno_description(err) == "parser is paused"
HttpParser.resume(p)
@test HttpParser.errno(p) == 0x00

ex = HttpParser.HttpParserError(0x1f)
@test ex.errno == 0x1f

Compat.@info("All assertions passed!")
