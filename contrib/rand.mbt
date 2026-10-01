///|
/// The name of the state temp that holds the seed of the per-render random
/// number generator.
///
/// Upstream stores the generator as a typed `State` extension.  MoonBit's
/// `State` has no typed extensions, so the current seed is kept in a state
/// temp instead (stored as the bit pattern of an `Int64`).
let rng_temp_key = "__minijinja_contrib_rng"

///|
/// A tiny xorshift random number generator (port of upstream's
/// `XorShiftRng`).  It is not cryptographically secure.
priv struct XorShiftRng {
  mut seed : UInt64
}

///|
fn XorShiftRng::new(seed : UInt64?) -> XorShiftRng {
  { seed: seed.unwrap_or_else(entropy_seed), }
}

///|
/// Returns the generator of a render state.  On first use the generator is
/// seeded from the `RAND_SEED` variable (if it is an unsigned integer) or
/// from a platform entropy source.  Call [`XorShiftRng::store`] after use to
/// persist the advanced state.
fn XorShiftRng::for_state(state : @minijinja.State) -> XorShiftRng {
  match state.get_temp(rng_temp_key) {
    Some(v) if v.as_i64() is Some(bits) =>
      { seed: bits.reinterpret_as_uint64(), }
    _ => {
      let seed = match state.lookup("RAND_SEED") {
        Some(v) => value_to_u64(v)
        None => None
      }
      let rng = XorShiftRng::new(seed)
      rng.store(state)
      rng
    }
  }
}

///|
/// Persists the generator state in the render state.
fn XorShiftRng::store(self : XorShiftRng, state : @minijinja.State) -> Unit {
  state.set_temp(
    rng_temp_key,
    @minijinja.Value::from_int64(self.seed.reinterpret_as_int64()),
  )
  |> ignore
}

///|
fn XorShiftRng::next(self : XorShiftRng) -> UInt64 {
  self.seed = self.seed ^ (self.seed << 13)
  self.seed = self.seed ^ (self.seed >> 7)
  self.seed = self.seed ^ (self.seed << 17)
  self.seed
}

///|
/// A random index in `0..max` (port of `next_usize`).
fn XorShiftRng::next_usize(self : XorShiftRng, max : Int) -> Int {
  let v = (self.random() * max.to_double()).to_int64()
  if v < 0L {
    0
  } else if v > 0x7FFFFFFFL {
    0x7FFFFFFF
  } else {
    v.to_int()
  }
}

///|
/// A random float in `0.0..=1.0`.
fn XorShiftRng::random(self : XorShiftRng) -> Double {
  self.next().to_double() / @uint64.MAX_VALUE.to_double()
}

///|
/// A random integer in `lower..upper`.
fn XorShiftRng::random_range(
  self : XorShiftRng,
  lower : Int64,
  upper : Int64,
) -> Int64 {
  (self.random() * (upper - lower).to_double()).to_int64() + lower
}

///|
/// Port of `u64::try_from(Value)`: accepts non-negative integers, bools and
/// floats with an integral value.
fn value_to_u64(v : @minijinja.Value) -> UInt64? {
  match v.kind() {
    Bool => Some(if v.is_true() { 1UL } else { 0UL })
    Number =>
      if v.is_integer() {
        match v.as_i64() {
          Some(i) =>
            if i >= 0L {
              Some(i.reinterpret_as_uint64())
            } else {
              None
            }
          // too large for an Int64: parse the decimal representation
          None => parse_u64(v.to_string())
        }
      } else {
        match v.as_f64() {
          Some(f) if f.to_int64().to_double() == f && f >= 0.0 =>
            Some(f.to_int64().reinterpret_as_uint64())
          _ => None
        }
      }
    _ => None
  }
}

///|
fn parse_u64(s : String) -> UInt64? {
  if s.is_empty() {
    return None
  }
  let mut rv = 0UL
  for c in s {
    guard c is ('0'..='9') else { return None }
    let digit = (c.to_int() - '0'.to_int()).to_uint64()
    if rv > (@uint64.MAX_VALUE - digit) / 10UL {
      return None
    }
    rv = rv * 10UL + digit
  }
  Some(rv)
}

///|
let entropy_counter : Ref[UInt64] = { val: 0UL, }

///|
/// A non-constant seed: platform entropy when available, otherwise the
/// current time mixed with a counter.
fn entropy_seed() -> UInt64 {
  let seed = match @env.rand(8) {
    Some(bytes) if bytes.length() == 8 => {
      let mut rv = 0UL
      for b in bytes {
        rv = (rv << 8) | b.to_uint64()
      }
      rv
    }
    _ => {
      entropy_counter.val += 1UL
      splitmix64(@env.now() ^ (entropy_counter.val * 0x9E3779B97F4A7C15UL))
    }
  }
  // xorshift must not be seeded with zero
  if seed == 0UL {
    0x2545F4914F6CDD1DUL
  } else {
    seed
  }
}

///|
fn splitmix64(x : UInt64) -> UInt64 {
  let mut z = x + 0x9E3779B97F4A7C15UL
  z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9UL
  z = (z ^ (z >> 27)) * 0x94D049BB133111EBUL
  z ^ (z >> 31)
}
