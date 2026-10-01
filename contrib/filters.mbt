///|
/// The (small) HTML entity table used by [`striptags`].
///
/// Upstream optionally ships the full HTML5 entity table (the
/// `html_entities` feature); this port only includes the default table.
let html_entities : FixedArray[(String, String)] = [
  ("amp", "&"),
  ("gt", ">"),
  ("lt", "<"),
  ("quot", "\""),
]

///|
/// Port of `i64::try_from(Value)`: accepts integers, bools and floats with
/// an integral value.
fn value_to_i64(v : @minijinja.Value) -> Int64? {
  try v.convert() catch {
    _ => None
  } noraise {
    i => Some(i)
  }
}

///|
/// Port of `usize::try_from(Value)` (bounded to `Int`).
fn value_to_usize(v : @minijinja.Value) -> Int? {
  match value_to_i64(v) {
    Some(i) if i >= 0L && i <= 0x7FFFFFFFL => Some(i.to_int())
    _ => None
  }
}

///|
/// Returns a plural suffix if the value is not 1, '1', or an object of
/// length 1.
///
/// By default, the plural suffix is 's' and the singular suffix is
/// empty (''). You can specify a singular suffix as the first argument (or
/// `None`, for the default). You can specify a plural suffix as the second
/// argument (or `None`, for the default).
///
/// ```jinja
/// {{ users|length }} user{{ users|pluralize }}.
/// ```
///
/// ```jinja
/// {{ entities|length }} entit{{ entities|pluralize("y", "ies") }}.
/// ```
///
/// ```jinja
/// {{ platypuses|length }} platypus{{ platypuses|pluralize(None, "es") }}.
/// ```
pub fn pluralize(
  v : @minijinja.Value,
  singular? : @minijinja.Value,
  plural? : @minijinja.Value,
) -> @minijinja.Value raise @minijinja.TemplateError {
  let is_singular = match v.len() {
    Some(len) => len == 1
    None =>
      match value_to_i64(v) {
        Some(val) => val == 1L
        None =>
          raise @minijinja.TemplateError::new(
            InvalidOperation,
            "Pluralize argument is not an integer, or a sequence / object with a length but of type \{v.kind()}",
          )
      }
  }
  let (rv, default) = if is_singular { (singular, "") } else { (plural, "s") }
  match rv {
    Some(rv) if !rv.is_undefined() && !rv.is_none() => rv
    _ => @minijinja.Value::from_string(default)
  }
}

///|
/// Chooses a random element from a sequence or string.
///
/// The random number generated can be seeded with the `RAND_SEED`
/// global context variable.
///
/// ```jinja
/// {{ [1, 2, 3, 4]|random }}
/// ```
pub fn random(
  state : @minijinja.State,
  seq : @minijinja.Value,
) -> @minijinja.Value raise @minijinja.TemplateError {
  match seq.kind() {
    Seq | String => {
      let len = seq.len().unwrap_or(0)
      let rng = XorShiftRng::for_state(state)
      let idx = rng.next_usize(len)
      rng.store(state)
      let selected = seq.get_item_by_index(idx)
      if seq.kind() == String && seq.is_safe() {
        match selected.as_str() {
          Some(value) => @minijinja.Value::from_safe_string(value)
          None => selected
        }
      } else {
        selected
      }
    }
    _ =>
      raise @minijinja.TemplateError::new(
        InvalidOperation,
        "can only select random elements from sequences",
      )
  }
}

///|
/// Formats the value like a "human-readable" file size.
///
/// For example. 13 kB, 4.1 MB, 102 Bytes, etc.  Per default decimal prefixes
/// are used (Mega, Giga, etc.),  if the second parameter is set to true the
/// binary prefixes are used (Mebi, Gibi).
///
/// ```mbt check
/// test {
///   inspect(@contrib.filesizeformat(1500.0), content="1.5 kB")
///   inspect(@contrib.filesizeformat(1024.0, binary=true), content="1.0 KiB")
/// }
/// ```
pub fn filesizeformat(value : Double, binary? : Bool = false) -> String {
  let bin_prefixes = ["KiB", "MiB", "GiB", "TiB", "PiB", "EiB", "ZiB", "YiB"]
  let si_prefixes = ["kB", "MB", "GB", "TB", "PB", "EB", "ZB", "YB"]
  let (prefixes, base) = if binary {
    (bin_prefixes, 1024.0)
  } else {
    (si_prefixes, 1000.0)
  }
  if value == 1.0 {
    return "1 Byte"
  }
  let (sign, value) = if value < 0.0 { ("-", -value) } else { ("", value) }
  if value < base {
    "\{sign}\{@rfmt.f64_display(value)} Bytes"
  } else {
    for idx, prefix in prefixes {
      let unit = @math.pow(base, idx.to_double() + 2.0)
      if value < unit || idx == prefixes.length() - 1 {
        return "\{sign}\{@rfmt.format_fixed(base * value / unit, 1)} \{prefix}"
      }
    }
    abort("unreachable")
  }
}

///|
/// Returns a truncated copy of the string.
///
/// The string will be truncated to the specified length, with an ellipsis
/// appended if truncation occurs. By default, the filter tries to preserve
/// whole words.
///
/// ```jinja
/// {{ "Hello World"|truncate(length=5) }}
/// ```
///
/// The filter accepts a few keyword arguments:
/// * `length`: maximum length of the output string (defaults to 255)
/// * `killwords`: set to `true` if you want to cut text exactly at length; if
///   `false`, the filter will preserve last word (defaults to `false`)
/// * `end`: if you want a specific ellipsis sign you can specify it (defaults
///   to "...")
/// * `leeway`: determines the tolerance margin before truncation occurs
///   (defaults to the `TRUNCATE_LEEWAY` variable or 5)
///
/// The truncation only occurs if the string length exceeds both the
/// specified length and the leeway margin combined.  The specified length
/// is inclusive of the end string (ellipsis).  Lengths are counted in
/// Unicode scalar values.
///
/// The result is safe if either the value or the end string is safe; the
/// other part is escaped in that case.
pub fn truncate(
  state : @minijinja.State,
  value : @minijinja.Value,
  kwargs : @minijinja.Kwargs,
) -> @minijinja.Value raise @minijinja.TemplateError {
  if value.is_none() || value.is_undefined() {
    return @minijinja.Value::from_string("")
  }
  guard value.as_str() is Some(s) else {
    raise @minijinja.TemplateError::new(
      InvalidOperation,
      "expected string, got \{value.kind()}",
    )
  }
  let length = kwargs.get_usize("length").unwrap_or(255)
  let killwords = kwargs.get_bool("killwords").unwrap_or(false)
  let end = kwargs
    .get_opt("end")
    .unwrap_or(@minijinja.Value::from_string("..."))
  guard end.as_str() is Some(end_str) else {
    raise @minijinja.TemplateError::new(
      InvalidOperation,
      "value is not a string",
    )
  }
  let leeway = match kwargs.get_usize("leeway") {
    Some(leeway) => leeway
    None =>
      match state.lookup("TRUNCATE_LEEWAY") {
        Some(v) => value_to_usize(v).unwrap_or(5)
        None => 5
      }
  }
  kwargs.assert_all_used()
  let end_len = end_str.char_length()
  if length < end_len {
    raise @minijinja.TemplateError::new(
      InvalidOperation,
      "expected length >= \{end_len}, got \{length}",
    )
  }
  let chars = s.iter().to_array()
  if chars.length() <= length + leeway {
    return value
  }
  let trunc_pos = length - end_len
  let kept = chars[:trunc_pos]
  let kept = if killwords {
    kept
  } else {
    let last_space = for i = kept.length() - 1; i >= 0; i = i - 1 {
      if kept[i] == ' ' {
        break Some(i)
      }
    } nobreak {
      None
    }
    match last_space {
      Some(last_space) => kept[:last_space]
      None => kept
    }
  }
  let truncated = String::from_iter(kept.iter())
  if value.is_safe() || end.is_safe() {
    let result = StringBuilder()
    if value.is_safe() {
      result.write_string(truncated)
    } else {
      result.write_string(escape(state, truncated))
    }
    if end.is_safe() {
      result.write_string(end_str)
    } else {
      result.write_string(escape(state, end_str))
    }
    @minijinja.Value::from_safe_string(result.to_string())
  } else {
    @minijinja.Value::from_string(truncated + end_str)
  }
}

///|
/// Escapes a string with the core `escape` filter.
fn escape(
  state : @minijinja.State,
  s : String,
) -> String raise @minijinja.TemplateError {
  call_builtin_filter("escape", state, [@minijinja.Value::from_string(s)]).to_string()
}

///|
/// Counts the words in a string.
///
/// A word is a run of letters (general category `L`), numeric characters
/// and underscores.
///
/// ```jinja
/// {{ "Hello world!"|wordcount }}
/// ```
pub fn wordcount(value : @minijinja.Value) -> @minijinja.Value {
  let s = value.as_str().unwrap_or("")
  let mut count = 0
  let mut in_word = false
  // Iterate through characters, counting transitions from non-word to word
  // chars
  for c in s {
    let is_word_char = @unicode.is_letter(c) ||
      @unicode.is_numeric(c) ||
      c == '_'
    if is_word_char && !in_word {
      count += 1
      in_word = true
    } else if !is_word_char {
      in_word = false
    }
  }
  @minijinja.Value::from_int(count)
}

///|
/// Wrap a string to the given width.
///
/// This is a port of the subset of the `textwrap` crate used by upstream
/// (optimal-fit wrapping, ASCII space word separation, hyphen splitting,
/// non unicode aware widths).
///
/// **Keyword arguments:**
///
/// - `width`: Maximum length of wrapped lines (default: 79)
/// - `break_long_words`: If a word is longer than width, break it across
///   lines (default: true)
/// - `break_on_hyphens`: If a word contains hyphens, it may be split across
///   lines (default: true)
/// - `wrapstring`: String to join each wrapped line (default: newline)
pub fn wordwrap(
  value : @minijinja.Value,
  kwargs : @minijinja.Kwargs,
) -> @minijinja.Value raise @minijinja.TemplateError {
  let s = value.as_str().unwrap_or("")
  let width = kwargs.get_usize("width").unwrap_or(79)
  let break_long_words = kwargs.get_bool("break_long_words").unwrap_or(true)
  let break_on_hyphens = kwargs.get_bool("break_on_hyphens").unwrap_or(true)
  let wrapstring = kwargs.get_str("wrapstring").unwrap_or("\n")
  kwargs.assert_all_used()
  // When break_on_hyphens is false, we want to preserve hyphenated words
  // entirely.  So we disable hyphen splitting and also disable breaking long
  // words to ensure hyphenated words stay together.
  let (hyphen_splitter, break_words) = if break_on_hyphens {
    (true, break_long_words)
  } else {
    (false, false)
  }
  // Handle empty/whitespace-only input
  if @unicode.trim(s).is_empty() {
    return @minijinja.Value::from_string("")
  }
  // Process paragraphs sequentially into final string
  let acc = StringBuilder()
  for i, p in rust_lines(s) {
    if i > 0 {
      acc.write_string(wrapstring)
    }
    if !@unicode.trim(p).is_empty() {
      // Wrap the paragraph and join with wrapstring
      let wrapped = textwrap(p, width~, hyphen_splitter~, break_words~)
      for j, line in wrapped {
        if j > 0 {
          acc.write_string(wrapstring)
        }
        acc.write_string(line)
      }
    }
  }
  @minijinja.Value::from_string(acc.to_string())
}

///|
priv enum StripState {
  Text
  TagStart
  Tag
  Entity
  CommentStart1
  CommentStart2
  Comment
  CommentEnd1
  CommentEnd2
}

///|
/// Performs HTML tag stripping and unescaping.
///
/// ```mbt check
/// test {
///   inspect(
///     @contrib.striptags("<span>Hello &amp; World</span>"),
///     content="Hello & World",
///   )
/// }
/// ```
///
/// The filter only knows about `&amp;`, `&lt;`, `&gt;`, `&quot;` and numeric
/// character references (upstream's optional full HTML5 entity table is not
/// ported).
pub fn striptags(s : String) -> String {
  let rv : Array[Char] = []
  let entity_buffer = StringBuilder()
  let mut state : StripState = Text
  fn push_char(c : Char) {
    if @unicode.is_whitespace(c) {
      if rv.last() is Some(last) && !@unicode.is_whitespace(last) {
        rv.push(' ')
      }
    } else {
      rv.push(c)
    }
  }

  let chars : Array[Char?] = s.iter().map(c => Some(c)).to_array()
  chars.push(None)
  for c in chars {
    state = match (c, state) {
      (Some('<'), Text) => TagStart
      (Some('>'), Tag | TagStart) => Text
      (Some('!'), TagStart) => CommentStart1
      (Some('-'), CommentStart1) => CommentStart2
      (Some('-'), CommentStart2) => Comment
      (_, CommentStart1 | CommentStart2) => Tag
      (_, Tag | TagStart) => Tag
      (Some('&'), Text) => {
        entity_buffer.reset()
        Entity
      }
      (Some('-'), Comment) => CommentEnd1
      (Some('-'), CommentEnd1) => CommentEnd2
      (Some('>'), CommentEnd2) => Text
      (_, CommentEnd1 | CommentEnd2) => Comment
      (_, Entity) => {
        let cc = c.unwrap_or('\u{0}')
        if cc == '\u{0}' ||
          cc == ';' ||
          cc == '<' ||
          cc == '&' ||
          @unicode.is_whitespace(cc) {
          let entity = entity_buffer.to_string()
          match resolve_numeric_entity(entity) {
            Some(resolved) => push_char(resolved)
            None =>
              match lookup_entity(entity) {
                Some(resolved) =>
                  for rc in resolved {
                    push_char(rc)
                  }
                None => {
                  rv.push('&')
                  for ec in entity {
                    rv.push(ec)
                  }
                  if cc == ';' {
                    rv.push(';')
                  }
                }
              }
          }
          if cc == '<' {
            Tag
          } else if cc == '&' {
            entity_buffer.reset()
            Entity
          } else {
            if @unicode.is_whitespace(cc) {
              push_char(cc)
            }
            Text
          }
        } else {
          if c is Some(c) {
            entity_buffer.write_char(c)
          }
          Entity
        }
      }
      (Some(c), Text) => {
        push_char(c)
        Text
      }
      (_, state) => state
    }
  }
  while rv.last() is Some(last) && @unicode.is_whitespace(last) {
    rv.pop() |> ignore
  }
  String::from_array(rv)
}

///|
fn lookup_entity(name : String) -> String? {
  for entry in html_entities {
    if entry.0 == name {
      return Some(entry.1)
    }
  }
  None
}

///|
fn resolve_numeric_entity(entity : String) -> Char? {
  guard entity is ['#', .. num_str] else { return None }
  let code = match num_str {
    ['x' | 'X', .. hex] => parse_u32(hex, 16)
    _ => parse_u32(num_str, 10)
  }
  match code {
    Some(code) if code <= 0x10FFFFL && !(code >= 0xD800L && code <= 0xDFFFL) =>
      Some(code.to_int().unsafe_to_char())
    _ => None
  }
}

///|
/// Port of `u32::from_str_radix` (an optional `+` sign followed by at least
/// one digit; overflow fails).
fn parse_u32(s : StringView, radix : Int) -> Int64? {
  let digits = if s is ['+', .. rest] { rest } else { s }
  if digits.is_empty() {
    return None
  }
  let mut rv = 0L
  for c in digits {
    let d = match c {
      '0'..='9' => c.to_int() - '0'.to_int()
      'a'..='z' => c.to_int() - 'a'.to_int() + 10
      'A'..='Z' => c.to_int() - 'A'.to_int() + 10
      _ => return None
    }
    if d >= radix {
      return None
    }
    rv = rv * radix.to_int64() + d.to_int64()
    if rv > 0xFFFFFFFFL {
      return None
    }
  }
  Some(rv)
}
