///|
/// A port of the parts of Rust's `core::fmt::Formatter` that matter for
/// reproducing `{:?}` and `{:#?}` output: the alternate flag and the
/// `PadAdapter` indentation used by the debug builders.
pub struct Formatter {
  priv buf : StringBuilder
  /// `true` for `{:#?}` style output.
  alternate : Bool
  priv mut depth : Int
  priv mut on_newline : Bool
}

///|
pub fn Formatter::new(alternate? : Bool = false) -> Formatter {
  { buf: StringBuilder(), alternate, depth: 0, on_newline: false, }
}

///|
/// Returns everything written so far.
pub fn Formatter::to_string(self : Formatter) -> String {
  self.buf.to_string()
}

///|
fn Formatter::write_pad(self : Formatter) -> Unit {
  for _ in 0..<self.depth {
    self.buf.write_string("    ")
  }
}

///|
/// Writes a string, inserting the indentation of all active pad adapters at
/// the start of each line.
pub fn Formatter::write_str(self : Formatter, s : StringView) -> Unit {
  if self.depth == 0 {
    self.buf.write_view(s)
    if s.length() > 0 {
      self.on_newline = s[s.length() - 1] == '\n'
    }
    return
  }
  let mut start = 0
  let len = s.length()
  while start < len {
    let mut end = start
    while end < len && s[end] != '\n' {
      end += 1
    }
    if end < len {
      end += 1
    }
    if self.on_newline {
      self.write_pad()
    }
    let part = s.view(start_offset=start, end_offset=end)
    self.on_newline = part[part.length() - 1] == '\n'
    self.buf.write_view(part)
    start = end
  }
}

///|
pub fn Formatter::write_char(self : Formatter, c : Char) -> Unit {
  if self.depth > 0 && self.on_newline {
    self.write_pad()
  }
  self.buf.write_char(c)
  self.on_newline = c == '\n'
}

///|
/// Runs `f` inside a pad adapter (one more level of indentation).
fn Formatter::padded(self : Formatter, f : () -> Unit) -> Unit {
  self.depth += 1
  f()
  self.depth -= 1
}

///|
/// Port of `Formatter::debug_struct`.
pub struct DebugStruct {
  priv fmt : Formatter
  priv mut has_fields : Bool
}

///|
pub fn Formatter::debug_struct(self : Formatter, name : String) -> DebugStruct {
  self.write_str(name)
  { fmt: self, has_fields: false, }
}

///|
pub fn DebugStruct::field(
  self : DebugStruct,
  name : String,
  value : (Formatter) -> Unit,
) -> DebugStruct {
  let f = self.fmt
  if f.alternate {
    if !self.has_fields {
      f.write_str(" {\n")
    }
    f.padded(() => {
      f.write_str(name)
      f.write_str(": ")
      value(f)
      f.write_str(",\n")
    })
  } else {
    f.write_str(if self.has_fields { ", " } else { " { " })
    f.write_str(name)
    f.write_str(": ")
    value(f)
  }
  self.has_fields = true
  self
}

///|
pub fn DebugStruct::finish(self : DebugStruct) -> Unit {
  if self.has_fields {
    self.fmt.write_str(if self.fmt.alternate { "}" } else { " }" })
  }
}

///|
/// Port of `Formatter::debug_tuple`.
pub struct DebugTuple {
  priv fmt : Formatter
  priv mut fields : Int
  priv empty_name : Bool
}

///|
pub fn Formatter::debug_tuple(self : Formatter, name : String) -> DebugTuple {
  self.write_str(name)
  { fmt: self, fields: 0, empty_name: name.is_empty(), }
}

///|
pub fn DebugTuple::field(
  self : DebugTuple,
  value : (Formatter) -> Unit,
) -> DebugTuple {
  let f = self.fmt
  if f.alternate {
    if self.fields == 0 {
      f.write_str("(\n")
    }
    f.padded(() => {
      value(f)
      f.write_str(",\n")
    })
  } else {
    f.write_str(if self.fields == 0 { "(" } else { ", " })
    value(f)
  }
  self.fields += 1
  self
}

///|
pub fn DebugTuple::finish(self : DebugTuple) -> Unit {
  if self.fields > 0 {
    if self.fields == 1 && self.empty_name && !self.fmt.alternate {
      self.fmt.write_str(",")
    }
    self.fmt.write_str(")")
  }
}

///|
/// Port of `Formatter::debug_list` (also used for sets with other braces).
pub struct DebugList {
  priv fmt : Formatter
  priv mut has_fields : Bool
  priv close : String
}

///|
pub fn Formatter::debug_list(self : Formatter) -> DebugList {
  self.write_str("[")
  { fmt: self, has_fields: false, close: "]", }
}

///|
pub fn Formatter::debug_set(self : Formatter) -> DebugList {
  self.write_str("{")
  { fmt: self, has_fields: false, close: "}", }
}

///|
pub fn DebugList::entry(
  self : DebugList,
  value : (Formatter) -> Unit,
) -> DebugList {
  let f = self.fmt
  if f.alternate {
    if !self.has_fields {
      f.write_str("\n")
    }
    f.padded(() => {
      value(f)
      f.write_str(",\n")
    })
  } else {
    if self.has_fields {
      f.write_str(", ")
    }
    value(f)
  }
  self.has_fields = true
  self
}

///|
pub fn DebugList::finish(self : DebugList) -> Unit {
  self.fmt.write_str(self.close)
}

///|
/// Port of `Formatter::debug_map`.
pub struct DebugMap {
  priv fmt : Formatter
  priv mut has_fields : Bool
}

///|
pub fn Formatter::debug_map(self : Formatter) -> DebugMap {
  self.write_str("{")
  { fmt: self, has_fields: false, }
}

///|
pub fn DebugMap::entry(
  self : DebugMap,
  key : (Formatter) -> Unit,
  value : (Formatter) -> Unit,
) -> DebugMap {
  let f = self.fmt
  if f.alternate {
    if !self.has_fields {
      f.write_str("\n")
    }
    f.padded(() => {
      key(f)
      f.write_str(": ")
      value(f)
      f.write_str(",\n")
    })
  } else {
    if self.has_fields {
      f.write_str(", ")
    }
    key(f)
    f.write_str(": ")
    value(f)
  }
  self.has_fields = true
  self
}

///|
pub fn DebugMap::finish(self : DebugMap) -> Unit {
  self.fmt.write_str("}")
}
