// A port of the parts of the `textwrap` crate (0.16, with the `smawk`
// feature but without `unicode-linebreak` / `unicode-width`) that upstream's
// `wordwrap` filter uses: `WordSeparator::AsciiSpace`, the `HyphenSplitter`
// and `NoHyphenation` word splitters, `break_words` and the optimal-fit
// wrapping algorithm (with the default penalties).
//
// Words are represented as ranges of character indexes into the line that
// is being wrapped.

///|
/// A piece of a line (port of `textwrap::core::Word`).
priv struct Word {
  /// start of the word
  start : Int
  /// end of the word (exclusive), which is also the start of the trailing
  /// whitespace
  end : Int
  /// end of the trailing whitespace (exclusive)
  ws_end : Int
  /// the penalty string (`""` or `"-"`) added if a line breaks after the word
  penalty : String
  /// cached width in columns
  width : Int
}

///|
fn Word::whitespace_width(self : Word) -> Double {
  (self.ws_end - self.end).to_double()
}

///|
fn Word::penalty_width(self : Word) -> Double {
  self.penalty.length().to_double()
}

///|
/// Port of `Word::from`: the trailing spaces of `chars[start:stop]` become
/// the whitespace of the word.
fn Word::from_range(chars : Array[Char], start : Int, stop : Int) -> Word {
  let mut end = stop
  while end > start && chars[end - 1] == ' ' {
    end -= 1
  }
  {
    start,
    end,
    ws_end: stop,
    penalty: "",
    width: display_width(chars, start, end),
  }
}

///|
/// Port of `skip_ansi_escape_sequence`.  `pos` points after `ch`; returns
/// the position after the skipped characters or `None` if nothing was
/// skipped.
fn skip_ansi_escape_sequence(
  ch : Char,
  chars : Array[Char],
  pos : Int,
  stop : Int,
) -> Int? {
  if ch != '\u{1b}' {
    return None
  }
  let mut pos = pos
  let next = if pos < stop {
    pos += 1
    Some(chars[pos - 1])
  } else {
    None
  }
  if next == Some('[') {
    // CSI sequence: skip until a "final byte" in the range 0x40–0x7E.
    while pos < stop {
      let c = chars[pos]
      pos += 1
      if c.to_int() >= 0x40 && c.to_int() <= 0x7e {
        break
      }
    }
  } else if next == Some(']') {
    // OSC sequence: extends until "\x1b\\" or BEL.
    let mut last = ']'
    while pos < stop {
      let c = chars[pos]
      pos += 1
      if c == '\u{07}' || (c == '\\' && last == '\u{1b}') {
        break
      }
      last = c
    }
  }
  Some(pos)
}

///|
/// The width of a character without the `unicode-width` feature.
fn ch_width(ch : Char) -> Int {
  if ch.to_int() < 0x1100 {
    1
  } else {
    2
  }
}

///|
/// Port of `textwrap::core::display_width` for `chars[start:stop]`.
fn display_width(chars : Array[Char], start : Int, stop : Int) -> Int {
  let mut width = 0
  let mut pos = start
  while pos < stop {
    let ch = chars[pos]
    pos += 1
    if skip_ansi_escape_sequence(ch, chars, pos, stop) is Some(next) {
      pos = next
      continue
    }
    width += ch_width(ch)
  }
  width
}

///|
/// Port of `find_words_ascii_space`.
fn find_words_ascii_space(chars : Array[Char]) -> Array[Word] {
  let words = []
  let mut start = 0
  let mut in_whitespace = false
  for idx, ch in chars {
    if in_whitespace && ch != ' ' {
      words.push(Word::from_range(chars, start, idx))
      start = idx
    }
    in_whitespace = ch == ' '
  }
  if start < chars.length() {
    words.push(Word::from_range(chars, start, chars.length()))
  }
  words
}

///|
/// Port of `WordSplitter::HyphenSplitter::split_points` (absolute indexes).
fn hyphen_split_points(chars : Array[Char], word : Word) -> Array[Int] {
  let splits = []
  for idx in word.start..<word.end {
    if chars[idx] != '-' {
      continue
    }
    // We only use hyphens that are surrounded by alphanumeric characters.
    // This is to avoid splitting on repeated hyphens, such as those found
    // in --foo-bar.
    if idx > word.start &&
      @unicode.is_alphanumeric(chars[idx - 1]) &&
      idx + 1 < word.end &&
      @unicode.is_alphanumeric(chars[idx + 1]) {
      splits.push(idx + 1)
    }
  }
  splits
}

///|
/// Port of `split_words`.
fn split_words(
  chars : Array[Char],
  words : Array[Word],
  hyphen_splitter : Bool,
) -> Array[Word] {
  let rv = []
  for word in words {
    let mut prev = word.start
    let points = if hyphen_splitter {
      hyphen_split_points(chars, word)
    } else {
      []
    }
    for idx in points {
      let need_hyphen = chars[idx - 1] != '-'
      rv.push({
        start: prev,
        end: idx,
        ws_end: idx,
        penalty: if need_hyphen {
          "-"
        } else {
          ""
        },
        width: display_width(chars, prev, idx),
      })
      prev = idx
    }
    if prev < word.end || prev == word.start {
      rv.push({
        start: prev,
        end: word.end,
        ws_end: word.ws_end,
        penalty: word.penalty,
        width: display_width(chars, prev, word.end),
      })
    }
  }
  rv
}

///|
/// Port of `Word::break_apart`.
fn break_apart(
  chars : Array[Char],
  word : Word,
  line_width : Int,
  out : Array[Word],
) -> Unit {
  let mut offset = word.start
  let mut width = 0
  let mut pos = word.start
  while pos < word.end {
    let idx = pos
    let ch = chars[pos]
    pos += 1
    if skip_ansi_escape_sequence(ch, chars, pos, word.end) is Some(next) {
      pos = next
      continue
    }
    if width > 0 && width + ch_width(ch) > line_width {
      out.push({ start: offset, end: idx, ws_end: idx, penalty: "", width, })
      offset = idx
      width = ch_width(ch)
    } else {
      width += ch_width(ch)
    }
  }
  if offset < word.end {
    out.push({
      start: offset,
      end: word.end,
      ws_end: word.ws_end,
      penalty: word.penalty,
      width,
    })
  }
}

///|
/// Port of `break_words`.
fn break_long_words(
  chars : Array[Char],
  words : Array[Word],
  line_width : Int,
) -> Array[Word] {
  let rv = []
  for word in words {
    if word.width > line_width {
      break_apart(chars, word, line_width, rv)
    } else {
      rv.push(word)
    }
  }
  rv
}

///|
/// Port of `smawk::smawk_inner` (column minima of a totally monotone
/// matrix).
fn smawk_inner(
  matrix : (Int, Int) -> Double,
  rows : Array[Int],
  cols : Array[Int],
  minima : Array[Int],
) -> Unit {
  if cols.is_empty() {
    return
  }
  let stack : Array[Int] = []
  for r in rows {
    while !stack.is_empty() &&
          matrix(stack[stack.length() - 1], cols[stack.length() - 1]) >
          matrix(r, cols[stack.length() - 1]) {
      stack.pop() |> ignore
    }
    if stack.length() != cols.length() {
      stack.push(r)
    }
  }
  let rows = stack
  let odd_cols = []
  for idx, c in cols {
    if idx % 2 == 1 {
      odd_cols.push(c)
    }
  }
  smawk_inner(matrix, rows, odd_cols, minima)
  let mut r = 0
  for c = 0; c < cols.length(); c = c + 2 {
    let col = cols[c]
    let mut row = rows[r]
    let last_row = if c == cols.length() - 1 {
      rows[rows.length() - 1]
    } else {
      minima[cols[c + 1]]
    }
    let mut pair = (matrix(row, col), row)
    while row != last_row {
      r += 1
      row = rows[r]
      let v = matrix(row, col)
      if v < pair.0 || (v == pair.0 && row < pair.1) {
        pair = (v, row)
      }
    }
    minima[col] = pair.1
  }
}

///|
/// Port of `smawk::online_column_minima`.
fn online_column_minima(
  initial : Double,
  size : Int,
  matrix : (Array[(Int, Double)], Int, Int) -> Double,
) -> Array[(Int, Double)] {
  let result = [(0, initial)]
  // State used by the algorithm.
  let mut finished = 0
  let mut base = 0
  let mut tentative = 0
  let m = (i : Int, j : Int) => matrix(result, i, j)
  // Keep going until we have finished all size columns.
  while finished < size - 1 {
    // First case: we have already advanced past the previous tentative
    // value.  We make a new tentative value by applying smawk_inner to the
    // largest square submatrix that fits under the base.
    let i = finished + 1
    if i > tentative {
      let rows = Array::makei(finished + 1 - base, k => base + k)
      tentative = (finished + rows.length()).min(size - 1)
      let cols = Array::makei(tentative - finished, k => finished + 1 + k)
      let minima = Array::make(tentative + 1, 0)
      smawk_inner(m, rows, cols, minima)
      for col in cols {
        let row = minima[col]
        let v = m(row, col)
        if col >= result.length() {
          result.push((row, v))
        } else if v < result[col].1 {
          result[col] = (row, v)
        }
      }
      finished = i
      continue
    }
    // Second case: the new column minimum is on the diagonal.
    let diag = m(i - 1, i)
    if diag < result[i].1 {
      result[i] = (i - 1, diag)
      base = i - 1
      tentative = i
      finished = i
      continue
    }
    // Third case: row i-1 does not supply a column minimum in any column up
    // to tentative.
    if m(i - 1, tentative) >= result[tentative].1 {
      finished = i
      continue
    }
    // Fourth and final case: a new column minimum at tentative.
    base = i - 1
    tentative = i
    finished = i
  }
  result
}

///|
/// Port of `wrap_optimal_fit` with the default `Penalties`.  Returns the
/// ranges `[start, end)` of the fragments on each line.
fn wrap_optimal_fit(
  fragments : Array[Word],
  line_widths : Array[Double],
) -> Array[(Int, Int)] {
  let nline_penalty = 1000.0
  let overflow_penalty = 2500.0
  let short_last_line_fraction = 4.0
  let short_last_line_penalty = 25.0
  let hyphen_penalty = 25.0
  // The final line width is used for all remaining lines.
  let default_line_width = line_widths.last().unwrap_or(0.0)
  let widths = [0.0]
  let mut width = 0.0
  for fragment in fragments {
    width += fragment.width.to_double() + fragment.whitespace_width()
    widths.push(width)
  }
  // Port of `LineNumbers`: caches the line number of each break.
  let line_numbers = [0]
  fn get_line_number(i : Int, minima : Array[(Int, Double)]) -> Int {
    while line_numbers.length() < i + 1 {
      let pos = line_numbers.length()
      let line_number = 1 + get_line_number(minima[pos].0, minima)
      line_numbers.push(line_number)
    }
    line_numbers[i]
  }

  let minima = online_column_minima(0.0, widths.length(), (minima, i, j) => {
    // Line number for fragment `i`.
    let line_number = get_line_number(i, minima)
    let line_width = line_widths.get(line_number).unwrap_or(default_line_width)
    let target_width = if line_width > 1.0 { line_width } else { 1.0 }
    // Compute the width of a line spanning fragments[i..j] in constant
    // time.
    let line_width = widths[j] -
      widths[i] -
      fragments[j - 1].whitespace_width() +
      fragments[j - 1].penalty_width()
    // We compute cost of the line containing fragments[i..j].  We start
    // with values[i].1, which is the optimal cost for breaking before
    // fragments[i].  First, every extra line cost NLINE_PENALTY.
    let mut cost = minima[i].1 + nline_penalty
    // Next, we add a penalty depending on the line length.
    if line_width > target_width {
      // Lines that overflow get a hefty penalty.
      let overflow = line_width - target_width
      cost += overflow * overflow_penalty
    } else if j < fragments.length() {
      // Other lines (except for the last line) get a milder penalty which
      // depend on the size of the gap.
      let gap = target_width - line_width
      cost += gap * gap
    } else if i + 1 == j && line_width < target_width / short_last_line_fraction {
      // The last line can have any size gap, but we do add a penalty if
      // the line is very short (typically because it contains just a
      // single word).
      cost += short_last_line_penalty
    }
    // Finally, we discourage hyphens.
    if fragments[j - 1].penalty_width() > 0.0 {
      cost += hyphen_penalty
    }
    cost
  })
  let lines = []
  let mut pos = fragments.length()
  while true {
    let prev = minima[pos].0
    lines.push((prev, pos))
    pos = prev
    if pos == 0 {
      break
    }
  }
  lines.rev_in_place()
  lines
}

///|
/// The UTF-8 length of a string.
fn utf8_len(chars : Array[Char]) -> Int {
  let mut len = 0
  for c in chars {
    let cp = c.to_int()
    len += if cp < 0x80 {
      1
    } else if cp < 0x800 {
      2
    } else if cp < 0x10000 {
      3
    } else {
      4
    }
  }
  len
}

///|
/// Port of `textwrap::wrap` for a single line (no `\n`) with the options
/// used by the `wordwrap` filter.
fn textwrap(
  line : String,
  width~ : Int,
  hyphen_splitter~ : Bool,
  break_words~ : Bool,
) -> Array[String] {
  let chars = line.iter().to_array()
  // fast path (note: upstream compares the UTF-8 length with the width)
  if utf8_len(chars) < width {
    let mut end = chars.length()
    while end > 0 && chars[end - 1] == ' ' {
      end -= 1
    }
    return [String::from_array(chars[:end])]
  }
  let line_widths = [width.to_double(), width.to_double()]
  let words = find_words_ascii_space(chars)
  let split = split_words(chars, words, hyphen_splitter)
  let broken = if break_words {
    break_long_words(chars, split, width)
  } else {
    split
  }
  let lines = []
  let mut idx = 0
  for range in wrap_optimal_fit(broken, line_widths) {
    let (start, stop) = range
    if start == stop {
      lines.push("")
      continue
    }
    let last_word = broken[stop - 1]
    let mut len = 0
    for k in start..<stop {
      let word = broken[k]
      len += word.ws_end - word.start
    }
    len -= last_word.ws_end - last_word.end
    let result = StringBuilder()
    for c in chars[idx:idx + len] {
      result.write_char(c)
    }
    result.write_string(last_word.penalty)
    lines.push(result.to_string())
    idx += len + (last_word.ws_end - last_word.end)
  }
  lines
}
