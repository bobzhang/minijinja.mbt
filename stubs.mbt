///|
pub struct Environment {
  priv mut unknown_method_callback : ((State, Value, String, Array[Value]) -> Value raise TemplateError)?
}

///|
pub struct State {
  priv env : Environment
}

///|
pub fn State::env(self : State) -> Environment {
  self.env
}
