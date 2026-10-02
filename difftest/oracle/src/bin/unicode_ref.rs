//! Prints Rust's view of every code point (compared with the port's
//! internal/unicode tables by `difftest -- unicode`).
fn main() {
    let mut out = String::new();
    for cp in 0..0x110000u32 {
        let Some(c) = char::from_u32(cp) else { continue };
        let b = |x: bool| if x { '1' } else { '0' };
        let s = c.to_string();
        let up: String = s.to_uppercase();
        let lo: String = s.to_lowercase();
        out.push_str(&format!(
            "{:x};{};{};{}{}{}{}{}{}{}{}{};{:?}\n",
            cp,
            up.chars().map(|x| format!("{:x}", x as u32)).collect::<Vec<_>>().join(" "),
            lo.chars().map(|x| format!("{:x}", x as u32)).collect::<Vec<_>>().join(" "),
            b(c.is_alphabetic()),
            b(c.is_whitespace()),
            b(c.is_numeric()),
            b(c.is_uppercase()),
            b(c.is_lowercase()),
            b(unicode_ident::is_xid_start(c)),
            b(unicode_ident::is_xid_continue(c)),
            b(c.is_alphanumeric()),
            b(c == '_' || unicode_ident::is_xid_start(c)),
            s,
        ));
    }
    print!("{out}");
}
