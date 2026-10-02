//! Reads one JSON test case per line from stdin and writes one JSON result
//! per line to stdout: `{"ok": output}` or `{"err": message}`.
use std::error::Error as _;
use std::io::{BufRead, Write};

use minijinja::{Environment, UndefinedBehavior, Value};
use serde::Deserialize;

#[derive(Deserialize)]
struct Case {
    name: String,
    source: String,
    ctx: String,
    undefined: String,
    trim_blocks: bool,
    lstrip_blocks: bool,
    keep_trailing_newline: bool,
}

fn format_err(err: &minijinja::Error) -> String {
    let mut rv = err.to_string();
    let mut source = err.source();
    while let Some(err) = source {
        rv.push_str("\ncaused by: ");
        rv.push_str(&err.to_string());
        source = err.source();
    }
    rv
}

fn run(case: &Case) -> Result<String, String> {
    let mut env = Environment::new();
    env.set_undefined_behavior(match case.undefined.as_str() {
        "strict" => UndefinedBehavior::Strict,
        "semi_strict" => UndefinedBehavior::SemiStrict,
        "chainable" => UndefinedBehavior::Chainable,
        _ => UndefinedBehavior::Lenient,
    });
    env.set_trim_blocks(case.trim_blocks);
    env.set_lstrip_blocks(case.lstrip_blocks);
    env.set_keep_trailing_newline(case.keep_trailing_newline);
    // keep runaway templates bounded
    env.set_recursion_limit(100);
    let ctx: serde_json::Value = serde_json::from_str(&case.ctx).map_err(|e| e.to_string())?;
    env.add_template(&case.name, &case.source)
        .map_err(|e| format_err(&e))?;
    let tmpl = env.get_template(&case.name).map_err(|e| format_err(&e))?;
    tmpl.render(Value::from(minijinja::value::Serde(&ctx)))
        .map_err(|e| format_err(&e))
}

fn main() {
    std::panic::set_hook(Box::new(|_| {}));
    let stdin = std::io::stdin();
    let stdout = std::io::stdout();
    let mut out = stdout.lock();
    for line in stdin.lock().lines() {
        let line = line.expect("read");
        let case: Case = serde_json::from_str(&line).expect("bad case");
        let rv = match std::panic::catch_unwind(|| run(&case)) {
            Ok(Ok(s)) => serde_json::json!({ "ok": s }),
            Ok(Err(e)) => serde_json::json!({ "err": e }),
            Err(p) => {
                let msg = p
                    .downcast_ref::<String>()
                    .cloned()
                    .or_else(|| p.downcast_ref::<&str>().map(|s| s.to_string()))
                    .unwrap_or_default();
                serde_json::json!({ "panic": msg })
            }
        };
        writeln!(out, "{}", rv).unwrap();
        out.flush().unwrap();
    }
}
