// The template loader.
//
// The engine's loader callback is synchronous while file I/O goes through
// `moonbitlang/async`.  Templates are therefore loaded on demand with a
// restart strategy: when the engine asks for a file that was not read yet
// the loader records it as pending and reports it as missing.  Once the
// render (or expression / dump) finishes, all pending files are read
// asynchronously and the operation is run again from scratch.  Every round
// reads at least one new file, so this terminates; the final round sees
// exactly the same sources upstream's synchronous loader would.

///|
priv enum LoadState {
  Loaded(String)
  Missing
  Failed(String)
}

///|
priv struct FileLoader {
  allow_include : Bool
  safe_paths : Array[String]
  template_name : String
  template_source : String?
  stdin_used_for_data : Bool
  cache : Map[String, LoadState]
  pending : Array[String]
}

///|
fn FileLoader::new(
  config : Config,
  template_name : String,
  template_source : String?,
  stdin_used_for_data : Bool,
) -> FileLoader {
  {
    allow_include: config.allow_include,
    safe_paths: config.safe_paths,
    template_name,
    template_source,
    stdin_used_for_data,
    cache: {},
    pending: [],
  }
}

///|
/// The synchronous loader callback handed to the environment.
fn FileLoader::load(
  self : FileLoader,
  name : String,
) -> String? raise @minijinja.TemplateError {
  if !self.allow_include && name != self.template_name {
    return None
  }
  if name == stdin_stdout {
    if self.stdin_used_for_data {
      raise @minijinja.TemplateError::new(
        InvalidOperation,
        "cannot load template from stdin when data is from stdin",
      )
    }
  } else if name == self.template_name && self.template_source is Some(source) {
    return Some(source)
  } else if !self.safe_paths.is_empty() &&
    !self.safe_paths.iter().any(p => path_starts_with(name, p)) {
    raise @minijinja.TemplateError::new(
      InvalidOperation,
      "Cannot include template from non-trusted path",
    )
  }
  match self.cache.get(name) {
    Some(Loaded(source)) => Some(source)
    Some(Missing) => None
    Some(Failed(msg)) =>
      raise @minijinja.TemplateError::new(TemplateNotFound, msg)
    None => {
      if !self.pending.contains(name) {
        self.pending.push(name)
      }
      None
    }
  }
}

///|
/// Reads a pending template (or stdin) into the cache.
async fn FileLoader::fetch(self : FileLoader, io : Io, name : String) -> Unit {
  let state = if name == stdin_stdout {
    let bytes = io.stdin() catch {
      err =>
        return self.cache.set(
          name,
          Failed("failed to read template from stdin: \{describe_error(err).0}"),
        )
    }
    try @utf8.decode(bytes) catch {
      _ => Failed("failed to read template from stdin: invalid UTF-8")
    } noraise {
      source => Loaded(source)
    }
  } else {
    let bytes = @fs.read_file(name).binary() catch {
      @os_error.OSError(_) as err if err.is_ENOENT() =>
        return self.cache.set(name, Missing)
      err =>
        return self.cache.set(
          name,
          Failed("cannot find template: \{describe_error(err).0}"),
        )
    }
    try @utf8.decode(bytes) catch {
      _ => Failed("cannot find template: stream did not contain valid UTF-8")
    } noraise {
      source => Loaded(source)
    }
  }
  self.cache[name] = state
}

///|
/// Runs `f`, loading the templates it requests until it no longer asks for
/// templates that were not read yet.
async fn[T] FileLoader::run(self : FileLoader, io : Io, f : () -> T raise) -> T {
  for ;; {
    self.pending.clear()
    let result = try f() catch {
      err => {
        if self.pending.is_empty() {
          raise err
        }
        None
      }
    } noraise {
      v => Some(v)
    }
    if self.pending.is_empty() && result is Some(v) {
      return v
    }
    let pending = self.pending.copy()
    for name in pending {
      self.fetch(io, name)
    }
  }
}
