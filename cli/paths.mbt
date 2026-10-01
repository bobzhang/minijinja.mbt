// Minimal POSIX path helpers (the subset of `std::path` the CLI needs).

///|
fn is_absolute(path : String) -> Bool {
  path.has_prefix("/")
}

///|
/// `Path::join`: an absolute `name` replaces `base`.
fn path_join(base : String, name : String) -> String {
  if base == "" || is_absolute(name) {
    name
  } else if base.has_suffix("/") {
    base + name
  } else {
    base + "/" + name
  }
}

///|
/// `Path::parent` (returning `""` when there is no parent).
fn path_parent(path : String) -> String {
  let trimmed = trim_trailing_slashes(path)
  match trimmed.rev_find("/") {
    Some(0) => "/"
    Some(idx) => trimmed.view(end_offset=idx).to_owned()
    None => ""
  }
}

///|
fn trim_trailing_slashes(path : String) -> String {
  let mut end = path.length()
  while end > 1 && path[end - 1] == '/' {
    end -= 1
  }
  path.view(end_offset=end).to_owned()
}

///|
/// The file name component of a path.
fn path_file_name(path : String) -> String {
  let trimmed = trim_trailing_slashes(path)
  match trimmed.rev_find("/") {
    Some(idx) => trimmed.view(start_offset=idx + 1).to_owned()
    None => trimmed
  }
}

///|
/// `Path::extension`: the part of the file name after the last `.` (a
/// leading dot does not start an extension).
fn path_extension(path : String) -> String? {
  let name = path_file_name(path)
  match name.rev_find(".") {
    Some(idx) if idx > 0 => Some(name.view(start_offset=idx + 1).to_owned())
    _ => None
  }
}

///|
/// The normal components of a path (`.` and empty components are dropped,
/// like `Path::components` does).
fn path_components(path : String) -> Array[String] {
  let rv = []
  for part in path.split("/") {
    if part != "" && part != "." {
      rv.push(part.to_owned())
    }
  }
  rv
}

///|
/// `Path::starts_with`: component wise prefix check.
fn path_starts_with(path : String, prefix : String) -> Bool {
  if is_absolute(path) != is_absolute(prefix) {
    return false
  }
  let a = path_components(path)
  let b = path_components(prefix)
  if b.length() > a.length() {
    return false
  }
  for i, part in b {
    if a[i] != part {
      return false
    }
  }
  true
}

///|
/// Lexically normalizes a path (resolves `.` and `..` components).  This
/// stands in for upstream's `canonicalize` which needs file system access.
fn normalize_path(path : String) -> String {
  let absolute = is_absolute(path)
  let parts : Array[String] = []
  for part in path_components(path) {
    if part == ".." {
      match parts.last() {
        Some(last) if last != ".." => parts.pop() |> ignore
        _ => if !absolute { parts.push(part) }
      }
    } else {
      parts.push(part)
    }
  }
  let joined = parts.join("/")
  if absolute {
    "/" + joined
  } else if joined == "" {
    "."
  } else {
    joined
  }
}
