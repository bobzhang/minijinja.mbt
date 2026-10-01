///|
fn filter_format(
  state : State,
  args : Array[Value],
) -> Value raise TemplateError {
  let a = Args::new(state, args)
  let format_str = a.value()
  let format_args = a.rest_with_kwargs()
  ignore(format_args)
  ignore(format_str)
  raise TemplateError::new(
    InvalidOperation,
    "format filter is not implemented yet",
  )
}
