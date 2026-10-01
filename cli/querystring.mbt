// A small query string (form encoded) parser standing in for `serde_qs`.
// It supports `key=value` pairs separated by `&`, `+` for spaces, percent
// escapes and nested maps through brackets (`user[name]=Peter`).  All
// leaf values are strings.  When a key is repeated the last value wins.

///|
priv enum QsNode {
  Leaf(String)
  Branch(Map[String, QsNode])
}

///|
fn hex_value(c : Char) -> Int? {
  match c {
    '0'..='9' => Some(c.to_int() - '0'.to_int())
    'a'..='f' => Some(c.to_int() - 'a'.to_int() + 10)
    'A'..='F' => Some(c.to_int() - 'A'.to_int() + 10)
    _ => None
  }
}

///|
/// Decodes `+` and `%XX` escapes (the decoded bytes are read as UTF-8).
fn percent_decode(s : StringView) -> String {
  let bytes = @utf8.encode(s)
  let out = Array(capacity=bytes.length())
  let n = bytes.length()
  let mut i = 0
  while i < n {
    let b = bytes[i]
    if b == b'+' {
      out.push(b' ')
      i += 1
    } else if b == b'%' &&
      i + 2 < n &&
      hex_value(bytes[i + 1].to_char()) is Some(hi) &&
      hex_value(bytes[i + 2].to_char()) is Some(lo) {
      out.push((hi * 16 + lo).to_byte())
      i += 3
    } else {
      out.push(b)
      i += 1
    }
  }
  @utf8.decode_lossy(Bytes::from_array(out))
}

///|
/// Splits a key like `a[b][c]` into its segments `["a", "b", "c"]`.
fn split_qs_key(key : StringView) -> Array[String] {
  match key.find("[") {
    None | Some(0) => [percent_decode(key)]
    Some(idx) => {
      let segments = [percent_decode(key.view(end_offset=idx))]
      let mut rest = key.view(start_offset=idx)
      while rest.has_prefix("[") {
        guard rest.find("]") is Some(close) else { break }
        segments.push(
          percent_decode(rest.view(start_offset=1, end_offset=close)),
        )
        rest = rest.view(start_offset=close + 1)
      }
      segments
    }
  }
}

///|
fn qs_insert(
  m : Map[String, QsNode],
  segments : ArrayView[String],
  value : String,
) -> Unit {
  guard segments is [first, .. rest] else { return }
  if rest.length() == 0 {
    m[first] = Leaf(value)
    return
  }
  let child = match m.get(first) {
    Some(Branch(child)) => child
    _ => {
      let child : Map[String, QsNode] = Map([])
      m[first] = Branch(child)
      child
    }
  }
  qs_insert(child, rest, value)
}

///|
fn qs_to_value(node : QsNode) -> @minijinja.Value {
  match node {
    Leaf(s) => @minijinja.Value::from_string(s)
    Branch(m) =>
      @minijinja.Value::from_pairs(
        m.iter().map(kv => (kv.0, qs_to_value(kv.1))).to_array(),
      )
  }
}

///|
fn parse_querystring(s : String) -> @minijinja.Value {
  let root : Map[String, QsNode] = Map([])
  for pair in s.trim_end(chars="\r\n").split("&") {
    if pair.length() == 0 {
      continue
    }
    let (key, value) = match pair.find("=") {
      Some(idx) =>
        (
          pair.view(end_offset=idx),
          percent_decode(pair.view(start_offset=idx + 1)),
        )
      None => (pair, "")
    }
    qs_insert(root, split_qs_key(key), value)
  }
  qs_to_value(Branch(root))
}
