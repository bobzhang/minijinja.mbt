///|
/// Terminates the process with the given exit status (provided by the
/// `moonbitlang/async` wasm runtime, like its own `run_async_main` uses).
#unsafe_skip_stub_check
fn exit(code : Int) = "moonbitlang/async" "runtime/exit"
