// The `minijinja-cli` executable (`moon run cmd/minijinja -- --help`).

///|
async fn main_async() -> Unit {
  let args = @env.args()
  let args = if args.length() > 0 { args[1:] } else { args[:] }
  let outcome = @cli.run(args)
  if outcome.stdout != "" {
    @stdio.stdout.write(outcome.stdout)
  }
  if outcome.stderr != "" {
    @stdio.stderr.write(outcome.stderr)
  }
  if outcome.exit_code != 0 {
    exit(outcome.exit_code)
  }
}

///|
fn main {
  @async.run_async_main(main_async)
}
