///|
/// The object returned by [`cycler`].
priv struct Cycler {
  items : Array[@minijinja.Value]
  mut pos : Int
}

///|
impl @minijinja.Object for Cycler with fn repr(_self) {
  Plain
}

///|
impl @minijinja.Object for Cycler with fn call_method(self, state, name, args) {
  match name {
    "next" => {
      no_args(state, args)
      let idx = self.pos
      self.pos = (idx + 1) % self.items.length()
      self.items[idx]
    }
    _ => raise @minijinja.TemplateError::from_kind(UnknownMethod)
  }
}

///|
/// Renders like upstream's derived `Debug` implementation.
impl @minijinja.Object for Cycler with fn render(self) {
  let items = self.items.map(item => item.debug_string()).join(", ")
  Some("Cycler { items: [\{items}], pos: \{self.pos} }")
}

///|
/// Returns a cycler.
///
/// Similar to `loop.cycle`, but can be used outside loops or across
/// multiple loops. For example, render a list of folders and files in a
/// list, alternating giving them "odd" and "even" classes.  The items are
/// passed as a single sequence.
///
/// ```jinja
/// {% set row_class = cycler(["odd", "even"]) %}
/// <ul class="browser">
/// {% for folder in folders %}
///   <li class="folder {{ row_class.next() }}">{{ folder }}
/// {% endfor %}
/// {% for file in files %}
///   <li class="file {{ row_class.next() }}">{{ file }}
/// {% endfor %}
/// </ul>
/// ```
pub fn cycler(
  items : Array[@minijinja.Value],
) -> @minijinja.Value raise @minijinja.TemplateError {
  if items.is_empty() {
    raise @minijinja.TemplateError::new(
      InvalidOperation,
      "at least one value required",
    )
  }
  @minijinja.Value::from_object(Cycler::{ items, pos: 0, })
}

///|
/// The object returned by [`joiner`].
priv struct Joiner {
  sep : @minijinja.Value
  mut used : Bool
}

///|
impl @minijinja.Object for Joiner with fn repr(_self) {
  Plain
}

///|
impl @minijinja.Object for Joiner with fn call(self, state, args) {
  no_args(state, args)
  let used = self.used
  self.used = true
  if used {
    self.sep
  } else {
    @minijinja.Value::from_string("")
  }
}

///|
/// Renders like upstream's derived `Debug` implementation.
impl @minijinja.Object for Joiner with fn render(self) {
  Some("Joiner { sep: \{self.sep.debug_string()}, used: \{self.used} }")
}

///|
/// A tiny helper that can be used to “join” multiple sections.  A joiner is
/// passed a string and will return that string every time it’s called,
/// except the first time (in which case it returns an empty string). You can
/// use this to join things:
///
/// ```jinja
/// {% set pipe = joiner("|") %}
/// {% if categories %} {{ pipe() }}
/// Categories: {{ categories|join(", ") }}
/// {% endif %}
/// {% if author %} {{ pipe() }}
/// Author: {{ author() }}
/// {% endif %}
/// {% if can_edit %} {{ pipe() }}
/// <a href="?action=edit">Edit</a>
/// {% endif %}
/// ```
///
/// The default separator is `", "`.
pub fn joiner(sep? : @minijinja.Value) -> @minijinja.Value {
  @minijinja.Value::from_object(Joiner::{
    sep: sep.unwrap_or(@minijinja.Value::from_string(", ")),
    used: false,
  })
}

///|
/// Returns a random number in a given range.
///
/// If only one parameter is provided it's taken as exclusive upper bound
/// with 0 as lower bound, otherwise two parameters need to be passed for the
/// lower and upper bound.  Only integers are permitted.
///
/// The random number generated can be seeded with the `RAND_SEED` global
/// context variable.
pub fn randrange(state : @minijinja.State, n : Int64, m? : Int64) -> Int64 {
  let (lower, upper) = match m {
    None => (0L, n)
    Some(m) => (n, m)
  }
  let rng = XorShiftRng::for_state(state)
  let rv = rng.random_range(lower, upper)
  rng.store(state)
  rv
}

///|
let lipsum_words : FixedArray[String] = [
  "a", "ac", "accumsan", "ad", "adipiscing", "aenean", "aliquam", "aliquet", "amet",
  "ante", "aptent", "arcu", "at", "auctor", "augue", "bibendum", "blandit", "class",
  "commodo", "condimentum", "congue", "consectetuer", "consequat", "conubia", "convallis",
  "cras", "cubilia", "cum", "curabitur", "curae", "cursus", "dapibus", "diam", "dictum",
  "dictumst", "dignissim", "dis", "dolor", "donec", "dui", "duis", "egestas", "eget",
  "eleifend", "elementum", "elit", "enim", "erat", "eros", "est", "et", "etiam",
  "eu", "euismod", "facilisi", "facilisis", "fames", "faucibus", "felis", "fermentum",
  "feugiat", "fringilla", "fusce", "gravida", "habitant", "habitasse", "hac", "hendrerit",
  "hymenaeos", "iaculis", "id", "imperdiet", "in", "inceptos", "integer", "interdum",
  "ipsum", "justo", "lacinia", "lacus", "laoreet", "lectus", "leo", "libero", "ligula",
  "litora", "lobortis", "lorem", "luctus", "maecenas", "magna", "magnis", "malesuada",
  "massa", "mattis", "mauris", "metus", "mi", "molestie", "mollis", "montes", "morbi",
  "mus", "nam", "nascetur", "natoque", "nec", "neque", "netus", "nibh", "nisi", "nisl",
  "non", "nonummy", "nostra", "nulla", "nullam", "nunc", "odio", "orci", "ornare",
  "parturient", "pede", "pellentesque", "penatibus", "per", "pharetra", "phasellus",
  "placerat", "platea", "porta", "porttitor", "posuere", "potenti", "praesent", "pretium",
  "primis", "proin", "pulvinar", "purus", "quam", "quis", "quisque", "rhoncus", "ridiculus",
  "risus", "rutrum", "sagittis", "sapien", "scelerisque", "sed", "sem", "semper",
  "senectus", "sit", "sociis", "sociosqu", "ssociis", "sociosqu", "ssociis", "sociosqu",
  "ssociis", "sociosqu", "ssociis", "sociosqu", "ssoincidusociis", "sociosqu", "ssociis",
  "sociosqu", "ssociis", "sociosqu", "ssociis", "sociosqu", "ssociis", "vsociis",
  "sociosqu", "ssociis", "sociosqu", "ssociis", "sociosqu", "ssociis", "sociosqu",
  "ssociis", "s", "vulputate",
]

///|
/// Generates a random lorem ipsum.
///
/// The random number generated can be seeded with the `RAND_SEED` global
/// context variable.
///
/// The function accepts various keyword arguments:
///
/// * `n`: number of paragraphs to generate (also accepted positionally,
///   defaults to 5).
/// * `min`: minimum number of words to generate per paragraph (default 20).
/// * `max`: maximum number of words to generate per paragraph (default 100).
/// * `html`: set to `true` to generate HTML paragraphs instead.
pub fn lipsum(
  state : @minijinja.State,
  n? : Int,
  kwargs : @minijinja.Kwargs,
) -> @minijinja.Value raise @minijinja.TemplateError {
  let n_kwargs = kwargs.get_usize("n")
  let min = kwargs.get_usize("min").unwrap_or(20)
  let max = kwargs.get_usize("max").unwrap_or(100)
  let html = kwargs.get_bool("html").unwrap_or(false)
  let n = match n {
    Some(n) => n
    None => n_kwargs.unwrap_or(5)
  }
  let rv = StringBuilder()
  // tracks whether the output so far ends with a full stop
  let mut ends_with_fullstop = false
  let rng = XorShiftRng::for_state(state)
  for _ in 0..<n {
    let mut next_capitalized = true
    let mut last_fullstop = 0L
    let mut last = ""
    let count = rng.random_range(min.to_int64(), max.to_int64())
    for idx = 0L; idx < count; idx = idx + 1L {
      if idx > 0L {
        rv.write_char(' ')
      } else if html {
        rv.write_string("<p>")
      }
      let word = for ;; {
        let word = lipsum_words[rng.next_usize(lipsum_words.length())]
        if word != last {
          last = word
          break word
        }
      }
      if next_capitalized {
        for i, c in word.iter().to_array() {
          if i == 0 {
            rv.write_string(@unicode.char_to_upper(c))
          } else {
            rv.write_char(c)
          }
        }
        next_capitalized = false
      } else {
        rv.write_string(word)
      }
      ends_with_fullstop = false
      if idx - last_fullstop > rng.random_range(10L, 20L) {
        rv.write_char('.')
        ends_with_fullstop = true
        last_fullstop = idx
        next_capitalized = true
      }
    }
    if !ends_with_fullstop {
      rv.write_char('.')
    }
    if html {
      rv.write_string("</p>")
    }
    rv.write_string("\n\n")
    ends_with_fullstop = false
  }
  rng.store(state)
  if html {
    @minijinja.Value::from_safe_string(rv.to_string())
  } else {
    @minijinja.Value::from_string(rv.to_string())
  }
}
