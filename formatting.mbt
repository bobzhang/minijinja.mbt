///|
/// The supported format string styles.
pub(all) enum FormatStyle {
  /// Python's printf-style formatting (`"%s %d" % args`)
  Printf
  /// Python's `str.format` formatting (`"{} {:d}".format(args)`)
  StrFormat
} derive(Eq)

///|
priv enum FormatConversion {
  Other
  Character
} derive(Eq)

///|
priv enum PathElem {
  Attr(String)
  Key(String)
}

///|
priv enum FieldName {
  Kwarg(String, Array[PathElem])
  Positional(Int, Array[PathElem])
  MappingKey(String)
}

///|
priv enum Align {
  Left
  Right
  Center
} derive(Eq)

///|
priv struct FillAlign {
  fill : Char?
  align : Align
}

///|
priv enum FmtType {
  Default
  Binary
  Decimal
  Octal
  LowerHex
  UpperHex
  LowerE
  UpperE
  LowerF
  UpperF
  LowerG
  UpperG
  Char
  String
} derive(Eq)

///|
fn FmtType::description(self : FmtType) -> String {
  match self {
    Default => ""
    Binary => "binary format ('b')"
    Octal => "octal format ('o')"
    LowerHex => "hex format ('x')"
    UpperHex => "hex format ('X')"
    Decimal => "decimal format ('d')"
    LowerE => "scientific notation ('e')"
    UpperE => "scientific notation ('E')"
    LowerF => "fixed-point notation ('f')"
    UpperF => "fixed-point notation ('F')"
    LowerG => "general format ('g')"
    UpperG => "general format ('G')"
    Char => "character format ('c')"
    String => "string format ('s')"
  }
}

///|
priv enum Separator {
  Comma
  Underscore
} derive(Eq)

///|
/// Captures format spec for both printf-style and str.format style format
/// strings.
priv struct FormatSpec {
  fill_align : FillAlign?
  print_sign : Bool
  space_before_positive_num : Bool
  alternate_form : Bool
  zero_padded : Bool
  width : Int?
  integer_grouping : Separator?
  precision : Int?
  ty : FmtType
  format_style : FormatStyle
  /// UTF-8 byte offset within the input string where this spec begins
  location : Int
}

///|
/// A number to format: either an (absolute) integer or a float.
priv enum FNum {
  FInt(BigInt)
  FFloat(Double)
}

///|
fn fmt_err(msg : String) -> TemplateError {
  TemplateError::new(InvalidOperation, msg)
}

///|
fn FormatSpec::format(
  self : FormatSpec,
  val : Value,
) -> String raise TemplateError {
  if val is Bool(b) {
    return self.format_bool(b)
  }
  if cast_to_abs_integer(val) is Some((number, is_negative)) {
    return self.format_integer(number, is_negative)
  }
  match value_to_f64_opt(val) {
    Some(fp) => self.format_float(fp)
    None => self.format_str(val.to_string())
  }
}

///|
fn FormatSpec::type_conversion_err(
  self : FormatSpec,
  val_kind : String,
  ty : FmtType,
) -> TemplateError {
  fmt_err(
    "invalid format spec at offset \{self.location}; '\{val_kind}' cannot be formatted in \{ty.description()}",
  )
}

///|
fn cast_to_abs_integer(val : Value) -> (BigInt, Bool)? {
  if !val.is_integer() {
    return None
  }
  match val.to_i128() {
    Some(i) => Some((if i < 0N { -i } else { i }, i < 0N))
    None =>
      match val.to_u128() {
        Some(u) => Some((u, false))
        None => None
      }
  }
}

///|
fn FormatSpec::format_bool(
  self : FormatSpec,
  val : Bool,
) -> String raise TemplateError {
  let treat_as_integer = self.fill_align is Some(_) ||
    self.print_sign ||
    self.alternate_form ||
    self.zero_padded ||
    self.width is Some(_) ||
    self.precision is Some(_)
  match self.ty {
    Default if !treat_as_integer => {
      // Format "True" or "False" as a regular string, ignoring the precision
      let text = if val { "True" } else { "False" }
      self.apply_padding(text, Left)
    }
    String =>
      match self.format_style {
        Printf => {
          let text = if val { "True" } else { "False" }
          self.apply_padding(text, Right)
        }
        StrFormat => raise self.type_conversion_err("bool", String)
      }
    _ => self.format_integer(if val { 1N } else { 0N }, false)
  }
}

///|
fn FormatSpec::format_str(
  self : FormatSpec,
  text : String,
) -> String raise TemplateError {
  match self.ty {
    Default | String => {
      let default_align = match self.format_style {
        Printf => Align::Right
        StrFormat => Left
      }
      if self.precision is Some(p) {
        let chars = text.iter().to_array()
        if p < chars.length() {
          return self.apply_padding(
            String::from_array(chars[0:p].to_owned()),
            default_align,
          )
        }
      }
      self.apply_padding(text, default_align)
    }
    Char =>
      match self.format_style {
        StrFormat => raise self.type_conversion_err("string", self.ty)
        Printf => {
          let chars = text.iter().to_array()
          if chars.length() == 1 {
            self.format_char(chars[0])
          } else {
            raise fmt_err("\{self.ty.description()} requires integer or char")
          }
        }
      }
    _ => raise self.type_conversion_err("string", self.ty)
  }
}

///|
/// Formats the number in scientific form and returns mantissa and exponent.
fn mantissa_and_exp(val : FNum, precision : Int) -> (String, Int) {
  match val {
    FFloat(f) => @rfmt.format_exp_parts(f, precision)
    FInt(i) => {
      let s = i.to_string()
      if i.is_zero() {
        let mantissa = if precision > 0 {
          "0." + "0".repeat(precision)
        } else {
          "0"
        }
        return (mantissa, 0)
      }
      // strip trailing zeros for rounding
      let mut trail = s.length()
      while trail > 1 && s[trail - 1] == '0' {
        trail -= 1
      }
      let (digits, point) = @rfmt.round_digits(
        s.view(end_offset=trail).to_owned(),
        s.length(),
        precision + 1,
      )
      let padded = if digits.length() < precision + 1 {
        digits + "0".repeat(precision + 1 - digits.length())
      } else {
        digits
      }
      let mantissa = if precision > 0 {
        padded.view(end_offset=1).to_owned() +
        "." +
        padded.view(start_offset=1, end_offset=precision + 1).to_owned()
      } else {
        padded.view(end_offset=1).to_owned()
      }
      (mantissa, point - 1)
    }
  }
}

///|
fn format_fixed_num(val : FNum, precision : Int) -> String {
  match val {
    FFloat(f) => @rfmt.format_fixed(f, precision)
    // Rust ignores the precision when formatting integers
    FInt(i) => i.to_string()
  }
}

///|
fn format_exp_suffix(exp : Int) -> String {
  let sign = if exp < 0 { "-" } else { "+" }
  let abs = if exp < 0 { -exp } else { exp }
  let digits = abs.to_string()
  sign + (if digits.length() < 2 { "0" + digits } else { digits })
}

///|
fn FormatSpec::fix_decimal_point(self : FormatSpec, num : String) -> String {
  if self.precision is Some(0) && self.alternate_form {
    num + "."
  } else {
    num
  }
}

///|
fn FormatSpec::remove_insignificants(self : FormatSpec, num : String) -> String {
  if !self.alternate_form && num.contains(".") {
    let mut end = num.length()
    while end > 0 && num[end - 1] == '0' {
      end -= 1
    }
    while end > 0 && num[end - 1] == '.' {
      end -= 1
    }
    num.view(end_offset=end).to_owned()
  } else {
    num
  }
}

///|
fn FormatSpec::number_in_general_format(
  self : FormatSpec,
  val : FNum,
  is_uppercase : Bool,
) -> String {
  let precision = match self.precision {
    Some(0) => 1
    Some(p) => p
    None => 6
  }
  let (manti, exp) = mantissa_and_exp(val, precision - 1)
  if exp >= -4 && exp < precision {
    let decimal_places = precision - 1 - exp
    let num = format_fixed_num(val, decimal_places)
    self.group_decimal_num(self.remove_insignificants(num))
  } else {
    let manti = self.group_decimal_num(self.remove_insignificants(manti))
    manti + (if is_uppercase { "E" } else { "e" }) + format_exp_suffix(exp)
  }
}

///|
/// Groups the digits of a number into chunks separated by `separator`.
fn group_digits(num : String, separator : Char, group_size : Int) -> String {
  let prefix_len = num.length() % group_size
  let grouped = StringBuilder()
  grouped.write_view(num.view(end_offset=prefix_len))
  let mut has_content = prefix_len > 0
  let mut i = prefix_len
  while i < num.length() {
    if has_content {
      grouped.write_char(separator)
    }
    let end = if i + group_size < num.length() {
      i + group_size
    } else {
      num.length()
    }
    grouped.write_view(num.view(start_offset=i, end_offset=end))
    has_content = true
    i = end
  }
  grouped.to_string()
}

///|
fn FormatSpec::group_binary_num(
  self : FormatSpec,
  number : String,
) -> String raise TemplateError {
  match self.integer_grouping {
    Some(Comma) =>
      raise fmt_err(
        "invalid format spec at offset \{self.location}; ',' cannot be specified with \{self.ty.description()}",
      )
    Some(Underscore) => group_digits(number, '_', 4)
    None => number
  }
}

///|
fn FormatSpec::group_decimal_num(self : FormatSpec, number : String) -> String {
  let separator = match self.integer_grouping {
    Some(Comma) => ','
    Some(Underscore) => '_'
    None => return number
  }
  match number.find(".") {
    Some(idx) => {
      let integer = group_digits(
        number.view(end_offset=idx).to_owned(),
        separator,
        3,
      )
      integer + "." + number.view(start_offset=idx + 1).to_owned()
    }
    None => group_digits(number, separator, 3)
  }
}

///|
fn FormatSpec::format_integer(
  self : FormatSpec,
  val : BigInt,
  is_negative : Bool,
) -> String raise TemplateError {
  let mut sign = if is_negative {
    "-"
  } else if self.print_sign {
    "+"
  } else if self.space_before_positive_num {
    " "
  } else {
    ""
  }
  let number = match self.ty {
    Binary => self.group_binary_num(val.to_string(radix=2))
    Octal => self.group_binary_num(val.to_string(radix=8))
    LowerHex => self.group_binary_num(val.to_string(radix=16))
    UpperHex => self.group_binary_num(val.to_string(radix=16).to_upper())
    Default | Decimal => self.group_decimal_num(val.to_string())
    Char => {
      if is_negative {
        raise fmt_err("\{self.ty.description()} arg not in range(0x110000)")
      }
      if self.format_style == StrFormat {
        if self.print_sign || self.space_before_positive_num {
          raise fmt_err(
            "sign flags are not allowed with \{self.ty.description()}",
          )
        }
        if self.alternate_form {
          raise fmt_err(
            "invalid format spec at offset \{self.location}; '#' cannot be specified with \{self.ty.description()}",
          )
        }
        if self.integer_grouping is Some(sep) {
          let c = if sep == Comma { "," } else { "_" }
          raise fmt_err(
            "invalid format spec at offset \{self.location}; '\{c}' cannot be specified with \{self.ty.description()}",
          )
        }
      }
      if val > 0x10FFFFN || (val >= 0xD800N && val <= 0xDFFFN) {
        raise fmt_err("\{self.ty.description()} arg not in range(0x110000)")
      }
      return self.format_char(val.to_int().unsafe_to_char())
    }
    String =>
      if self.format_style == Printf {
        // printf-style formatting in Python ignores sign character flag '+'
        // when combined with 's' format.
        sign = if is_negative { "-" } else { "" }
        val.to_string()
      } else {
        raise self.type_conversion_err("integer", String)
      }
    LowerE | UpperE => {
      let (mant, exp) = mantissa_and_exp(FInt(val), self.precision.unwrap_or(6))
      let mant = self.group_decimal_num(self.fix_decimal_point(mant))
      mant +
      (if self.ty == LowerE { "e" } else { "E" }) +
      format_exp_suffix(exp)
    }
    LowerF | UpperF => {
      let prec = self.precision.unwrap_or(6)
      let num = if prec != 0 {
        val.to_string() + "." + "0".repeat(prec)
      } else {
        val.to_string()
      }
      self.group_decimal_num(self.fix_decimal_point(num))
    }
    LowerG | UpperG =>
      self.number_in_general_format(FInt(val), self.ty == UpperG)
  }
  self.format_number(number, sign)
}

///|
fn FormatSpec::format_float(
  self : FormatSpec,
  val : Double,
) -> String raise TemplateError {
  let is_sign_negative = val.reinterpret_as_int64() < 0L
  let sign = if is_sign_negative {
    "-"
  } else if self.print_sign && self.ty != String {
    "+"
  } else if !is_sign_negative && self.space_before_positive_num {
    " "
  } else {
    ""
  }
  let upper = self.ty is (UpperE | UpperF | UpperG)
  let nan = if upper { "NAN" } else { "nan" }
  let inf = if upper { "INF" } else { "inf" }
  match self.ty {
    String if self.format_style != Printf =>
      raise self.type_conversion_err("float", String)
    Default | String =>
      if val.is_nan() {
        self.format_number("nan", "")
      } else if val.is_inf() {
        self.format_number("inf", sign)
      } else if val == 0.0 {
        self.format_number("0", sign)
      } else {
        let mut num = self.number_in_general_format(FFloat(val.abs()), false)
        if !(num.contains(".") || num.contains("e") || num.contains("E")) {
          num = num + ".0"
        }
        self.format_number(num, sign)
      }
    LowerE | UpperE =>
      if val.is_nan() {
        self.format_number(nan, "")
      } else if val.is_inf() {
        self.format_number(inf, sign)
      } else {
        let precision = self.precision.unwrap_or(6)
        let (mant, exp) = mantissa_and_exp(FFloat(val.abs()), precision)
        let mant = self.group_decimal_num(self.fix_decimal_point(mant))
        let num = mant +
          (if upper { "E" } else { "e" }) +
          format_exp_suffix(exp)
        self.format_number(num, sign)
      }
    LowerF | UpperF =>
      if val.is_nan() {
        self.format_number(nan, "")
      } else if val.is_inf() {
        self.format_number(inf, sign)
      } else {
        let prec = self.precision.unwrap_or(6)
        let num = @rfmt.format_fixed(val.abs(), prec)
        let num = self.group_decimal_num(self.fix_decimal_point(num))
        self.format_number(num, sign)
      }
    LowerG | UpperG =>
      if val.is_nan() {
        self.format_number(nan, "")
      } else if val.is_inf() {
        self.format_number(inf, sign)
      } else if val == 0.0 {
        self.format_number("0", sign)
      } else {
        let num = self.number_in_general_format(FFloat(val.abs()), upper)
        self.format_number(num, sign)
      }
    Binary | Octal | LowerHex | UpperHex | Decimal | Char =>
      raise self.type_conversion_err("float", self.ty)
  }
}

///|
fn FormatSpec::apply_zero_padding(
  self : FormatSpec,
  num : String,
  fill_width : Int,
) -> String {
  let (sep, group_width) = match self.integer_grouping {
    Some(Comma) => (',', 3)
    Some(Underscore) =>
      match self.ty {
        Binary | Octal | LowerHex | UpperHex => ('_', 4)
        _ => ('_', 3)
      }
    None => return "0".repeat(fill_width) + num
  }
  let sep_str = sep.to_string()
  let first_separator = match num.find(".") {
    Some(point) =>
      match num.view(end_offset=point).find(sep_str) {
        Some(i) => i
        None => point
      }
    None =>
      match num.find(sep_str) {
        Some(i) => i
        None =>
          match (num.find("e"), num.find("E")) {
            (Some(i), _) | (None, Some(i)) => i
            _ => num.length()
          }
      }
  }
  let prefix = num.view(end_offset=first_separator).to_owned()
  let grouped_suffix = num.view(start_offset=first_separator).to_owned()
  let zero_padded_prefix = "0".repeat(fill_width) + prefix
  let grouped_prefix = group_digits(zero_padded_prefix, sep, group_width)
  // Trim extra chars from the beginning of the padded and grouped prefix.
  let trim_index = grouped_prefix.length() - prefix.length() - fill_width
  let grouped_prefix = grouped_prefix.view(start_offset=trim_index).to_owned()
  (if grouped_prefix.has_prefix(sep_str) { "0" } else { "" }) +
  grouped_prefix +
  grouped_suffix
}

///|
fn FormatSpec::format_number(
  self : FormatSpec,
  number : String,
  sign : String,
) -> String {
  let radix = if self.alternate_form {
    match self.ty {
      Binary => "0b"
      Octal => "0o"
      LowerHex => "0x"
      UpperHex => "0X"
      _ => ""
    }
  } else {
    ""
  }
  if self.zero_padded {
    let min_width = self.width.unwrap_or(0)
    let curr_width = utf8_len(sign) + radix.length() + utf8_len(number)
    if curr_width < min_width {
      sign + radix + self.apply_zero_padding(number, min_width - curr_width)
    } else {
      sign + radix + number
    }
  } else {
    self.apply_padding(sign + radix + number, Right)
  }
}

///|
fn FormatSpec::format_char(self : FormatSpec, c : Char) -> String {
  match self.format_style {
    Printf => {
      let align = match self.fill_align {
        Some(fa) => fa.align
        None => Right
      }
      self.apply_padding_with_width(c.to_string(), align, 1)
    }
    StrFormat =>
      match self.fill_align {
        Some(fa) => self.apply_padding_with_width(c.to_string(), fa.align, 1)
        None =>
          if self.zero_padded {
            match self.width {
              Some(min_width) if 1 < min_width =>
                "0".repeat(min_width - 1) + c.to_string()
              _ => c.to_string()
            }
          } else {
            self.apply_padding_with_width(c.to_string(), Right, 1)
          }
      }
  }
}

///|
fn FormatSpec::apply_padding_with_width(
  self : FormatSpec,
  text : String,
  default_align : Align,
  curr_width : Int,
) -> String {
  guard self.width is Some(min_width) && curr_width < min_width else {
    return text
  }
  let fill_width = min_width - curr_width
  let (fill_char, align) = match self.fill_align {
    Some({ fill: None, align, }) => (' ', align)
    Some({ fill: Some(f), align, }) => (f, align)
    None => (' ', default_align)
  }
  let fill = fill_char.to_string()
  match align {
    Left => text + fill.repeat(fill_width)
    Right => fill.repeat(fill_width) + text
    Center => {
      let left_width = fill_width / 2
      let right_width = fill_width - left_width
      fill.repeat(left_width) + text + fill.repeat(right_width)
    }
  }
}

///|
fn FormatSpec::apply_padding(
  self : FormatSpec,
  text : String,
  default_align : Align,
) -> String {
  // MiniJinja measures the width in UTF-8 bytes here
  self.apply_padding_with_width(text, default_align, utf8_len(text))
}

///|
/// Cursor over the format string.  Positions are UTF-16 indexes; offsets
/// reported in errors are converted to UTF-8 byte offsets like MiniJinja.
priv struct FmtCursor {
  source : String
  mut pos : Int
}

///|
fn FmtCursor::byte_pos(self : FmtCursor) -> Int {
  utf8_len(self.source.view(end_offset=self.pos).to_owned())
}

///|
fn FmtCursor::peek(self : FmtCursor) -> Int {
  unit_at(self.source, self.pos)
}

///|
fn FmtCursor::advance_if(self : FmtCursor, c : Char) -> Bool {
  if self.peek() == c.to_int() {
    self.pos += 1
    true
  } else {
    false
  }
}

///|
fn FmtCursor::is_end(self : FmtCursor) -> Bool {
  self.pos >= self.source.length()
}

///|
priv enum FmtToken {
  Literal(String)
  Replace(FieldName?, FormatSpec, Int)
}

///|
fn fmt_next_token(
  cursor : FmtCursor,
  style : FormatStyle,
) -> FmtToken? raise TemplateError {
  let delimiter = match style {
    Printf => '%'.to_int()
    StrFormat => '{'.to_int()
  }
  let start = cursor.pos
  let mut offset = 0
  let mut found_spec = false
  let mut escape_seq = false
  let src = cursor.source
  for ;; {
    let c = unit_at(src, start + offset)
    if c < 0 {
      break
    }
    if c == delimiter {
      if unit_at(src, start + offset + 1) == delimiter {
        escape_seq = true
        offset += 1
        break
      } else {
        found_spec = true
        break
      }
    } else if c == '}'.to_int() && style == StrFormat {
      if unit_at(src, start + offset + 1) == '}'.to_int() {
        escape_seq = true
        offset += 1
        break
      } else {
        let byte_offset = utf8_len(
          src.view(start_offset=start, end_offset=start + offset).to_owned(),
        )
        raise fmt_err(
          "invalid single '}' in format string at offset \{byte_offset}; use escape sequence '}}'",
        )
      }
    } else {
      offset += 1
    }
  }
  if offset > 0 {
    let lit = src.view(start_offset=start, end_offset=start + offset).to_owned()
    cursor.pos += offset
    if escape_seq {
      cursor.pos += 1
    }
    Some(Literal(lit))
  } else if found_spec {
    match style {
      Printf => Some(printf_replacement_field(cursor))
      StrFormat => Some(str_format_replacement_field(cursor))
    }
  } else {
    None
  }
}

///|
fn fmt_parse_number(cursor : FmtCursor) -> Int? raise TemplateError {
  let start = cursor.pos
  while is_digit_unit(cursor.peek()) {
    cursor.pos += 1
  }
  if cursor.pos == start {
    return None
  }
  let s = cursor.source.view(start_offset=start, end_offset=cursor.pos)
  match parse_usize(s) {
    Some(n) => Some(n)
    None =>
      raise fmt_err(
        "invalid integer in the format string at offset \{cursor.byte_pos()}",
      )
  }
}

///|
fn fmt_parse_type(
  cursor : FmtCursor,
  style : FormatStyle,
) -> FmtType raise TemplateError {
  let c = cursor.peek()
  let t : FmtType = if c < 0 {
    raise fmt_err(
      "incomplete format spec at offset \{cursor.byte_pos()}; missing conversion type",
    )
  } else {
    match c.unsafe_to_char() {
      'b' if style == StrFormat => Binary
      'd' => Decimal
      'i' if style == Printf => Decimal
      'e' => LowerE
      'E' => UpperE
      'f' => LowerF
      'F' => UpperF
      'g' => LowerG
      'G' => UpperG
      'o' => Octal
      'x' => LowerHex
      'X' => UpperHex
      'c' => Char
      's' => String
      '}' if style == StrFormat => return Default
      ch =>
        raise fmt_err(
          "invalid conversion type '\{ch}' in format spec at offset \{cursor.byte_pos()}",
        )
    }
  }
  cursor.pos += 1
  t
}

///|
fn fmt_parse_till(
  cursor : FmtCursor,
  end_delim : Char,
) -> String raise TemplateError {
  let start = cursor.pos
  let start_byte = cursor.byte_pos()
  for ;; {
    if cursor.advance_if(end_delim) {
      break
    } else if cursor.is_end() {
      raise fmt_err(
        "incomplete format key at offset \{start_byte}; missing closing '\{end_delim}'",
      )
    } else {
      cursor.pos += 1
    }
  }
  cursor.source.view(start_offset=start, end_offset=cursor.pos - 1).to_owned()
}

///|
fn printf_replacement_field(cursor : FmtCursor) -> FmtToken raise TemplateError {
  let location = cursor.byte_pos()
  // consume '%'
  cursor.pos += 1
  let field_name = if cursor.advance_if('(') {
    Some(FieldName::MappingKey(fmt_parse_till(cursor, ')')))
  } else {
    None
  }
  let spec = printf_parse_format_spec(cursor)
  Replace(field_name, spec, location)
}

///|
fn printf_parse_format_spec(
  cursor : FmtCursor,
) -> FormatSpec raise TemplateError {
  let location = cursor.byte_pos()
  let mut fill_align : FillAlign? = None
  let mut print_sign = false
  let mut space_before_positive_num = false
  let mut alternate_form = false
  let mut zero_padded = false
  for ;; {
    match cursor.peek() {
      0x23 => alternate_form = true // #
      0x30 => zero_padded = true // 0
      0x2D => fill_align = Some({ fill: None, align: Left, }) // -
      0x20 => space_before_positive_num = true
      0x2B => print_sign = true // +
      _ => break
    }
    cursor.pos += 1
  }
  if print_sign {
    // '+' flag overrides ' '
    space_before_positive_num = false
  }
  if fill_align is Some({ align: Left, .. }) {
    // '-' flag overrides '0' padding flag
    zero_padded = false
  }
  let mut width = fmt_parse_number(cursor)
  if zero_padded && width is None {
    zero_padded = false
    width = Some(0)
  }
  let precision = if cursor.advance_if('.') {
    fmt_parse_number(cursor)
  } else {
    None
  }
  // length modifier is ignored in Python
  match cursor.peek() {
    0x68 | 0x6C | 0x4C => cursor.pos += 1 // h l L
    _ => ()
  }
  let ty = fmt_parse_type(cursor, Printf)
  {
    fill_align,
    print_sign,
    space_before_positive_num,
    alternate_form,
    zero_padded,
    width,
    integer_grouping: None,
    precision,
    ty,
    format_style: Printf,
    location,
  }
}

///|
fn missing_arg_err(location : Int) -> TemplateError {
  fmt_err("missing an argument for format spec at offset '\{location}'")
}

///|
/// Does printf-style formatting.  `transform` may replace the value before
/// it is formatted (used for safe format strings).
fn format_printf_with(
  format_str : String,
  args : Array[Value],
  transform : (Value, FormatConversion) -> Value? raise TemplateError,
) -> String raise TemplateError {
  let cursor = { source: format_str, pos: 0, }
  let result = StringBuilder()
  let mut arg_index = 0
  while fmt_next_token(cursor, Printf) is Some(token) {
    match token {
      Literal(lit) => result.write_string(lit)
      Replace(field_name, format_spec, _) => {
        let arg = match field_name {
          Some(MappingKey(key)) =>
            match args.get(0) {
              Some(arg) => {
                if arg.kind() != Map {
                  raise fmt_err("format argument must be a mapping")
                }
                let val = arg.get_attr(key) catch {
                  _ => raise missing_arg_err(format_spec.location)
                }
                if val.is_undefined() {
                  raise missing_arg_err(format_spec.location)
                }
                val
              }
              None => raise missing_arg_err(format_spec.location)
            }
          _ =>
            match args.get(arg_index) {
              Some(arg) => {
                arg_index += 1
                arg
              }
              None => raise missing_arg_err(format_spec.location)
            }
        }
        let conversion = if format_spec.ty == Char {
          FormatConversion::Character
        } else {
          Other
        }
        let transformed = transform(arg, conversion)
        result.write_string(format_spec.format(transformed.unwrap_or(arg)))
      }
    }
  }
  result.to_string()
}

///|
fn str_format_replacement_field(
  cursor : FmtCursor,
) -> FmtToken raise TemplateError {
  let location = cursor.byte_pos()
  // consume '{'
  cursor.pos += 1
  let field_name = str_format_parse_field_name(cursor)
  let format_spec = if cursor.advance_if(':') {
    str_format_parse_format_spec(cursor)
  } else {
    {
      fill_align: None,
      print_sign: false,
      space_before_positive_num: false,
      alternate_form: false,
      zero_padded: false,
      width: None,
      integer_grouping: None,
      precision: None,
      ty: Default,
      format_style: StrFormat,
      location,
    }
  }
  if cursor.advance_if('}') {
    Replace(field_name, format_spec, location)
  } else {
    let c = cursor.peek()
    if c >= 0 {
      raise fmt_err(
        "expected closing '}' in format spec at offset \{location}; found '\{c.unsafe_to_char()}'",
      )
    } else {
      raise fmt_err("missing closing '}' in format spec at offset \{location}")
    }
  }
}

///|
fn str_format_parse_identifier(cursor : FmtCursor) -> String? {
  let start = cursor.pos
  for ;; {
    let c = cursor.peek()
    let ok = if c == '_'.to_int() {
      true
    } else if cursor.pos == start {
      c >= 0 && c < 0x80 && c.unsafe_to_char().is_ascii_alphabetic()
    } else {
      c >= 0 &&
      c < 0x80 &&
      (c.unsafe_to_char().is_ascii_alphabetic() || is_digit_unit(c))
    }
    if !ok {
      break
    }
    cursor.pos += 1
  }
  if cursor.pos > start {
    Some(
      cursor.source.view(start_offset=start, end_offset=cursor.pos).to_owned(),
    )
  } else {
    None
  }
}

///|
fn str_format_parse_path(
  cursor : FmtCursor,
) -> Array[PathElem] raise TemplateError {
  let elems = []
  for ;; {
    if cursor.advance_if('.') {
      match str_format_parse_identifier(cursor) {
        Some(attr) => elems.push(PathElem::Attr(attr))
        None =>
          raise fmt_err(
            "missing attribute name after '.' in format spec at offset \{cursor.byte_pos()}",
          )
      }
    } else if cursor.advance_if('[') {
      elems.push(PathElem::Key(fmt_parse_till(cursor, ']')))
    } else {
      break
    }
  }
  elems
}

///|
fn str_format_parse_field_name(
  cursor : FmtCursor,
) -> FieldName? raise TemplateError {
  match fmt_parse_number(cursor) {
    Some(num) => Some(Positional(num, str_format_parse_path(cursor)))
    None =>
      match str_format_parse_identifier(cursor) {
        Some(ident) => Some(Kwarg(ident, str_format_parse_path(cursor)))
        None => None
      }
  }
}

///|
fn str_format_parse_fill_align(cursor : FmtCursor) -> FillAlign? {
  let maybe_fill = char_at(cursor.source, cursor.pos)
  let fill_len = match maybe_fill {
    Some(c) => c.utf16_len()
    None => 0
  }
  let maybe_align = char_at(cursor.source, cursor.pos + fill_len)
  let (consumed, fa) : (Int, FillAlign) = match (maybe_fill, maybe_align) {
    (Some(f), Some('<')) => (fill_len + 1, { fill: Some(f), align: Left, })
    (Some(f), Some('>')) => (fill_len + 1, { fill: Some(f), align: Right, })
    (Some(f), Some('^')) => (fill_len + 1, { fill: Some(f), align: Center, })
    (Some('<'), _) => (1, { fill: None, align: Left, })
    (Some('>'), _) => (1, { fill: None, align: Right, })
    (Some('^'), _) => (1, { fill: None, align: Center, })
    _ => return None
  }
  cursor.pos += consumed
  Some(fa)
}

///|
fn str_format_parse_format_spec(
  cursor : FmtCursor,
) -> FormatSpec raise TemplateError {
  let location = cursor.byte_pos()
  let mut print_sign = false
  let mut space_before_positive_num = false
  let mut minus_sign = false
  let fill_align = str_format_parse_fill_align(cursor)
  if cursor.advance_if('+') {
    print_sign = true
  } else if cursor.advance_if(' ') {
    space_before_positive_num = true
  } else if cursor.advance_if('-') {
    minus_sign = true
  }
  let alternate_form = cursor.advance_if('#')
  let mut zero_padded = cursor.advance_if('0')
  let mut width = fmt_parse_number(cursor)
  if zero_padded && width is None {
    zero_padded = false
    width = Some(0)
  }
  let integer_grouping = if cursor.advance_if(',') {
    Some(Separator::Comma)
  } else if cursor.advance_if('_') {
    Some(Underscore)
  } else {
    None
  }
  let precision = if cursor.advance_if('.') {
    fmt_parse_number(cursor)
  } else {
    None
  }
  let ty = fmt_parse_type(cursor, StrFormat)
  if ty == Char {
    if print_sign || space_before_positive_num || minus_sign {
      raise fmt_err(
        "invalid format spec at offset \{location}; sign flags are not allowed with \{ty.description()}",
      )
    }
    if alternate_form {
      raise fmt_err(
        "invalid format spec at offset \{location}; '#' cannot be specified with \{ty.description()}",
      )
    }
    if integer_grouping is Some(grouping) {
      let sep = if grouping == Comma { "," } else { "_" }
      raise fmt_err(
        "invalid format spec at offset \{location}; '\{sep}' cannot be specified with \{ty.description()}",
      )
    }
  }
  {
    fill_align,
    print_sign,
    space_before_positive_num,
    alternate_form,
    zero_padded,
    width,
    integer_grouping,
    precision,
    ty,
    format_style: StrFormat,
    location,
  }
}

///|
fn str_format_get_nested_val(
  root : Value,
  path : Array[PathElem],
) -> Value raise TemplateError {
  let mut curr = root
  for elem in path {
    curr = match elem {
      Attr(attr) => curr.get_attr(attr)
      Key(index) =>
        match parse_usize(index) {
          Some(num) => curr.get_item_by_index(num)
          None => curr.get_attr(index)
        }
    }
  }
  if curr.is_undefined() {
    raise TemplateError::from_kind(UndefinedError)
  }
  curr
}

///|
fn str_format(
  format_str : String,
  all_args : Array[Value],
) -> String raise TemplateError {
  let cursor = { source: format_str, pos: 0, }
  let result = StringBuilder()
  fn missing(location : Int, source : TemplateError?) -> TemplateError {
    let err = fmt_err(
      "argument not found for format field at offset \{location}",
    )
    match source {
      Some(cause) => err.with_source(cause)
      None => err
    }
  }

  fn switch_err(location : Int, from : String, to : String) -> TemplateError {
    fmt_err(
      "cannot switch from \{from} to \{to} in field at offset \{location}",
    )
  }

  // split positional arguments and trailing kwargs
  let (args, kwargs) = match all_args.last() {
    Some(last) =>
      match Kwargs::extract(last) {
        Some(kw) => (all_args[0:all_args.length() - 1].to_owned(), kw)
        None => (all_args, Kwargs::from_pairs([]))
      }
    None => (all_args, Kwargs::from_pairs([]))
  }
  for arg in args {
    if arg.is_kwargs() {
      raise unexpected_kwargs()
    }
  }
  let mut arg_index = 0
  let mut auto_numbering = false
  let mut manual_numbering = false
  while fmt_next_token(cursor, StrFormat) is Some(token) {
    match token {
      Literal(lit) => result.write_string(lit)
      Replace(field_name, format_spec, location) => {
        let arg = match field_name {
          Some(Kwarg(key, path)) => {
            let val = match kwargs.peek(key) {
              Some(v) => v
              None =>
                raise missing(
                  location,
                  Some(
                    TemplateError::new(
                      MissingArgument,
                      "missing keyword argument '\{key}'",
                    ),
                  ),
                )
            }
            str_format_get_nested_val(val, path) catch {
              e => raise missing(location, Some(e))
            }
          }
          Some(Positional(index, path)) => {
            manual_numbering = true
            if auto_numbering {
              raise switch_err(
                location, "automatic numbering", "manual field specification",
              )
            }
            guard args.get(index) is Some(val) else {
              raise missing(location, None)
            }
            str_format_get_nested_val(val, path) catch {
              e => raise missing(location, Some(e))
            }
          }
          None => {
            auto_numbering = true
            if manual_numbering {
              raise switch_err(
                location, "manual field specification", "automatic numbering",
              )
            }
            guard args.get(arg_index) is Some(val) else {
              raise missing(location, None)
            }
            arg_index += 1
            val
          }
          Some(MappingKey(_)) => abort("unreachable")
        }
        result.write_string(format_spec.format(arg))
      }
    }
  }
  result.to_string()
}

///|
/// Formats a string with Python formatting semantics.
///
/// With [`FormatStyle::Printf`] the `%` operator semantics are used, with
/// [`FormatStyle::StrFormat`] the `str.format` semantics (keyword arguments
/// are passed as a trailing kwargs value).
pub fn format_string(
  style : FormatStyle,
  format_str : String,
  args : Array[Value],
) -> String raise TemplateError {
  match style {
    Printf => format_printf_with(format_str, args, (_, _) => None)
    StrFormat => str_format(format_str, args)
  }
}

///|
fn filter_format(
  state : State,
  args : Array[Value],
) -> Value raise TemplateError {
  let a = Args::new(state, args)
  let format_str = a.value()
  let format_args = a.rest_with_kwargs()
  guard format_str.as_str() is Some(string) else {
    raise TemplateError::new(InvalidOperation, "value is not a string")
  }
  if format_str.is_safe() {
    let output = format_printf_with(string, format_args, (value, conversion) => {
      if conversion == Character {
        raise TemplateError::new(
          InvalidOperation,
          "character formatting is not supported for safe format strings",
        )
      }
      // Strings are escaped before applying width and precision, matching
      // MarkupSafe.  Numbers stay typed so numeric conversion specifiers
      // continue to work.
      if value.is_safe() || value.kind() is (Bool | Number) {
        None
      } else {
        Some(Value::from_string(filter_escape(state, value).to_string()))
      }
    })
    Value::from_safe_string(output)
  } else {
    Value::from_string(format_string(Printf, string, format_args))
  }
}

///|
fn value_to_f64_opt(val : Value) -> Double? {
  try value_to_f64(val) catch {
    _ => None
  } noraise {
    f => Some(f)
  }
}
