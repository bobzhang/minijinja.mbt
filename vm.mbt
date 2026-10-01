///|
fn normalize_filter_test_name(name : String) -> String {
  let mut has_ws = false
  for i in 0..<name.length() {
    if is_ascii_ws_unit(name[i].to_int()) {
      has_ws = true
      break
    }
  }
  if !has_ws {
    return name
  }
  let sb = StringBuilder()
  for c in name {
    if !is_ascii_ws_unit(c.to_int()) {
      sb.write_char(c)
    }
  }
  sb.to_string()
}

///|
fn get_or_lookup_local(
  cache : Array[Value?],
  idx : Int,
  f : () -> Value?,
) -> Value? {
  if idx < 0 {
    f()
  } else {
    match cache[idx] {
      Some(rv) => Some(rv)
      None => {
        let val = f()
        cache[idx] = val
        val
      }
    }
  }
}

///|
/// Evaluates a template.
fn vm_eval(
  env : Environment,
  instructions : Instructions,
  root : Value,
  blocks : Map[String, Instructions],
  out : Output,
  auto_escape : AutoEscape,
) -> (Value?, State) raise TemplateError {
  let state = State::new(
    Context::new_with_frame(env, Frame::new(root.validate())),
    auto_escape,
    instructions,
    prepare_blocks(blocks),
  )
  let rv = eval_state(state, out)
  (rv, state)
}

///|
/// Evaluates a macro by temporarily switching the active state.
fn eval_macro(
  state : State,
  instructions : Instructions,
  pc : Int,
  out : Output,
  closure : Closure?,
  caller : Value?,
  args : Array[Value],
) -> Value? raise TemplateError {
  let context_base = state.ctx.clone_base()
  let ctx = Context::new_with_frame(state.env(), Frame::new(context_base))
  ctx.push_frame({ ..Frame::default(), closure_context: closure, })
  if caller is Some(caller) {
    ctx.store("caller", caller)
  }
  ctx.incr_depth(state.ctx.depth() + macro_recursion_cost)
  let old_ctx = state.ctx
  state.ctx = ctx
  let auto_escape = state.auto_escape
  let rv = {
    errdefer {
      state.ctx = old_ctx
    }
    state.with_execution_state(instructions, auto_escape, None, Isolate, state => {
      do_eval(state, out, { values: args.copy(), }, pc)
    })
  }
  state.ctx = old_ctx
  rv
}

///|
fn eval_state(state : State, out : Output) -> Value? raise TemplateError {
  do_eval(state, out, Stack::new(), 0)
}

///|
fn do_eval(
  state : State,
  out : Output,
  stack : Stack,
  pc : Int,
) -> Value? raise TemplateError {
  let initial_auto_escape = state.auto_escape
  let undefined_behavior = state.undefined_behavior()
  let strict_undefined = undefined_behavior is (Strict | SemiStrict)
  let auto_escape_stack : Array[AutoEscape] = []
  let mut next_loop_recursion_jump : (Int, Bool)? = None
  let mut loaded_filters : Array[Value?] = Array::make(MAX_LOCALS, None)
  let mut loaded_tests : Array[Value?] = Array::make(MAX_LOCALS, None)
  // If we are extending we are holding the instructions of the target parent
  // template here.  This is used to detect multiple extends and the
  // evaluation uses these instructions when it makes it to the end of the
  // instructions.
  let mut parent_instructions : Instructions? = None
  let mut pc = pc
  for ;; {
    let instr = match state.instructions.get(pc) {
      Some(instr) => instr
      None => {
        // when an extends statement appears in a template, when we hit the
        // last instruction we need to check if parent instructions were
        // stashed away (which means we found an extends tag which invoked
        // `LoadBlocks`).  If we do find instructions, we reset back to 0
        // from the new instructions.
        match parent_instructions {
          Some(instr) => {
            parent_instructions = None
            state.instructions = instr
          }
          None => break
        }
        out.end_capture(NoEscape) |> ignore
        pc = 0
        // because we swap out the instructions we also need to unload all
        // the filters and tests to ensure that we are not accidentally
        // reusing the local_ids for completely different filters.
        loaded_filters = Array::make(MAX_LOCALS, None)
        loaded_tests = Array::make(MAX_LOCALS, None)
        continue
      }
    }
    // the next program counter (`None` means `pc + 1`)
    let jump : Int? = try {
      if state.fuel_tracker is Some(tracker) {
        tracker.track(instr)
      }
      match instr {
        Swap => {
          let a = stack.pop()
          let b = stack.pop()
          stack.push(a)
          stack.push(b)
          None
        }
        EmitRaw(val) => {
          out.write_str(val)
          None
        }
        Emit => {
          let value = stack.pop()
          if state.env().formatter_is_default {
            if strict_undefined && value is Undefined(Default) {
              raise TemplateError::from_kind(UndefinedError)
            }
            write_escaped(out, state.auto_escape, value)
          } else {
            state.env().format(value, state, out)
          }
          None
        }
        StoreLocal(name) => {
          state.ctx.store(name, stack.pop())
          None
        }
        Lookup(name) => {
          stack.push(
            state.lookup(name).unwrap_or(Value::undefined()).validate(),
          )
          None
        }
        GetAttr(name) => {
          let a = stack.pop()
          // This is a common enough operation that it's interesting to
          // consider a fast path here.
          stack.push(
            match a.get_attr_fast(name) {
              Some(value) => value.validate()
              None => undefined_behavior.handle_undefined(a.is_undefined())
            },
          )
          None
        }
        SetAttr(name) => {
          let b = stack.pop()
          let a = stack.pop()
          match b {
            Object({ inner: Namespace(ns), .. }) => ns[name] = a
            _ =>
              raise TemplateError::new(
                InvalidOperation,
                "can only assign to namespaces, not \{b.kind()}",
              )
          }
          None
        }
        GetItem => {
          let a = stack.pop()
          let b = stack.pop()
          stack.push(
            match b.get_item_opt(a) {
              Some(value) => value.validate()
              None => undefined_behavior.handle_undefined(b.is_undefined())
            },
          )
          None
        }
        Slice => {
          let step = stack.pop()
          let stop = stack.pop()
          let b = stack.pop()
          let a = stack.pop()
          if a.is_undefined() && undefined_behavior is Strict {
            raise TemplateError::from_kind(UndefinedError)
          }
          stack.push(value_slice(a, b, stop, step))
          None
        }
        LoadConst(value) => {
          stack.push(value)
          None
        }
        BuildMap(pair_count) => {
          let map : Map[Value, Value] = Map([])
          stack.reverse_top(pair_count * 2)
          for _ in 0..<pair_count {
            let key = stack.pop()
            let value = stack.pop()
            map[key] = value
          }
          stack.push(Value::from_map(map))
          None
        }
        BuildKwargs(pair_count) => {
          let map : Map[Value, Value] = Map([])
          stack.reverse_top(pair_count * 2)
          for _ in 0..<pair_count {
            let key = stack.pop()
            let value = stack.pop()
            map[key] = value
          }
          stack.push(Value::from_kwargs_map(map))
          None
        }
        MergeKwargs(count) => {
          let sources = []
          for _ in 0..<count {
            sources.push(stack.pop())
          }
          sources.rev_in_place()
          stack.push(merge_kwargs(state, sources))
          None
        }
        BuildList(n) => {
          let count = match n {
            Some(n) => n
            None => stack.pop().as_usize().unwrap_or(0)
          }
          let v = []
          for _ in 0..<count {
            v.push(stack.pop())
          }
          v.rev_in_place()
          stack.push(Value::from_array(v))
          None
        }
        BuildTuple(n) => {
          let count = match n {
            Some(n) => n
            None => stack.pop().as_usize().unwrap_or(0)
          }
          let v = []
          for _ in 0..<count {
            v.push(stack.pop())
          }
          v.rev_in_place()
          stack.push(Value::from_tuple(v))
          None
        }
        UnpackList(count) => {
          unpack_list(stack, count)
          None
        }
        UnpackLists(count) => {
          let lists = []
          for _ in 0..<count {
            lists.push(stack.pop())
          }
          let mut len = 0
          for i = lists.length() - 1; i >= 0; i = i - 1 {
            for item in lists[i].try_iter() {
              stack.push(item)
              len += 1
            }
          }
          stack.push(Value::from_int(len))
          None
        }
        Add => binop(stack, value_add)
        Sub => binop(stack, value_sub)
        Mul => binop(stack, value_mul)
        Div => binop(stack, value_div)
        IntDiv => binop(stack, value_int_div)
        Rem => binop(stack, value_rem)
        Pow => binop(stack, value_pow)
        Eq => cmp_binop(stack, undefined_behavior, (a, b) => a == b)
        Ne => cmp_binop(stack, undefined_behavior, (a, b) => a != b)
        Gt => cmp_binop(stack, undefined_behavior, (a, b) => a.cmp(b) > 0)
        Gte => cmp_binop(stack, undefined_behavior, (a, b) => a.cmp(b) >= 0)
        Lt => cmp_binop(stack, undefined_behavior, (a, b) => a.cmp(b) < 0)
        Lte => cmp_binop(stack, undefined_behavior, (a, b) => a.cmp(b) <= 0)
        Not => {
          let a = stack.pop()
          stack.push(Value::from_bool(!undefined_behavior.is_true(a)))
          None
        }
        StringConcat => {
          let a = stack.pop()
          let b = stack.pop()
          undefined_behavior.assert_value_not_undefined(b)
          undefined_behavior.assert_value_not_undefined(a)
          stack.push(string_concat(b, a))
          None
        }
        In => {
          let a = stack.pop()
          let b = stack.pop()
          // the in-operator can fail if either side is undefined and we are
          // in strict mode.
          undefined_behavior.assert_iterable(a)
          undefined_behavior.assert_value_not_undefined(b)
          stack.push(value_contains(a, b))
          None
        }
        CompareAndPreserve(op) => {
          let b = stack.pop()
          let a = stack.pop()
          let result = match op {
            In | NotIn => {
              undefined_behavior.assert_iterable(b)
              undefined_behavior.assert_value_not_undefined(a)
              let contains = value_contains(b, a).is_true()
              if op is NotIn {
                !contains
              } else {
                contains
              }
            }
            _ => {
              undefined_behavior.assert_value_not_undefined(a)
              undefined_behavior.assert_value_not_undefined(b)
              match op {
                Eq => a == b
                Ne => a != b
                Lt => a.cmp(b) < 0
                Lte => a.cmp(b) <= 0
                Gt => a.cmp(b) > 0
                _ => a.cmp(b) >= 0
              }
            }
          }
          stack.push(b)
          stack.push(Value::from_bool(result))
          None
        }
        Neg => {
          let a = stack.pop()
          stack.push(value_neg(a))
          None
        }
        PushWith => {
          state.ctx.push_frame(Frame::default())
          None
        }
        PopFrame => {
          state.ctx.pop_frame() |> ignore
          None
        }
        PopLoopFrame => {
          let frame = state.ctx.pop_frame()
          match frame.current_loop {
            Some(l) =>
              match l.current_recursion_jump {
                Some((target, end_capture)) => {
                  l.current_recursion_jump = None
                  if end_capture {
                    stack.push(out.end_capture(state.auto_escape))
                  }
                  Some(target)
                }
                None => None
              }
            None => None
          }
        }
        IsUndefined => {
          let a = stack.pop()
          stack.push(Value::from_bool(a.is_undefined()))
          None
        }
        PushLoop(flags) => {
          let a = stack.pop()
          let jump = next_loop_recursion_jump
          next_loop_recursion_jump = None
          push_loop(state, a, flags, pc, jump)
          None
        }
        Iterate(jump_target) =>
          match state.ctx.next_loop_item() {
            Some(item) => {
              stack.push(item.validate())
              None
            }
            None => Some(jump_target)
          }
        PushDidNotIterate => {
          let did_not_iterate = match state.ctx.current_loop() {
            Some(l) => l.did_not_iterate()
            None => false
          }
          stack.push(Value::from_bool(did_not_iterate))
          None
        }
        Jump(jump_target) => Some(jump_target)
        JumpIfFalse(jump_target) => {
          let a = stack.pop()
          if !undefined_behavior.is_true(a) {
            Some(jump_target)
          } else {
            None
          }
        }
        JumpIfFalseOrPop(jump_target) =>
          if !undefined_behavior.is_true(stack.peek()) {
            Some(jump_target)
          } else {
            stack.pop() |> ignore
            None
          }
        JumpIfTrueOrPop(jump_target) =>
          if undefined_behavior.is_true(stack.peek()) {
            Some(jump_target)
          } else {
            stack.pop() |> ignore
            None
          }
        PushAutoEscape => {
          let a = stack.pop()
          auto_escape_stack.push(state.auto_escape)
          state.auto_escape = derive_auto_escape(a, initial_auto_escape)
          None
        }
        PopAutoEscape => {
          if auto_escape_stack.pop() is Some(ae) {
            state.auto_escape = ae
          }
          None
        }
        BeginCapture(mode) => {
          out.begin_capture(mode)
          None
        }
        EndCapture => {
          stack.push(out.end_capture(state.auto_escape))
          None
        }
        ApplyFilter(name, arg_count, local_id) => {
          let normalized_name = normalize_filter_test_name(name)
          let filter = match
            get_or_lookup_local(loaded_filters, local_id, () => {
              state.env().get_filter(normalized_name)
            }) {
            Some(f) => f
            None =>
              raise TemplateError::new(
                UnknownFilter,
                "filter \{normalized_name} is unknown",
              )
          }
          let args = stack.get_call_args(arg_count)
          let rv = filter.call(state, args)
          stack.drop_top(args.length())
          stack.push(rv)
          None
        }
        PerformTest(name, arg_count, local_id) => {
          let normalized_name = normalize_filter_test_name(name)
          let test_fn = match
            get_or_lookup_local(loaded_tests, local_id, () => {
              state.env().get_test(normalized_name)
            }) {
            Some(f) => f
            None =>
              raise TemplateError::new(
                UnknownTest,
                "test \{normalized_name} is unknown",
              )
          }
          let args = stack.get_call_args(arg_count)
          let rv = test_fn.call(state, args)
          stack.drop_top(args.length())
          stack.push(Value::from_bool(rv.is_true()))
          None
        }
        CallFunction(name, arg_count) => {
          let args = stack.get_call_args(arg_count)
          // super is a special function reserved for super-ing into blocks.
          let rv = if name == "super" {
            if !args.is_empty() {
              raise TemplateError::new(
                InvalidOperation,
                "super() takes no arguments",
              )
            }
            perform_super(state, out, true)
          } else {
            match state.lookup(name) {
              Some(Object({ inner: Loop(loop_object), .. })) => {
                // calling loops is a special operation that starts the
                // recursion process.
                if args.length() != 1 {
                  raise TemplateError::new(
                    InvalidOperation,
                    "loop() takes one argument",
                  )
                }
                guard loop_object.recurse_jump_target is Some(target) else {
                  raise TemplateError::new(
                    InvalidOperation,
                    "cannot recurse outside of recursive loop",
                  )
                }
                next_loop_recursion_jump = Some((pc + 1, true))
                out.begin_capture(Capture)
                return_jump(target)
              }
              Some(func) => Push(func.call(state, args))
              None =>
                raise TemplateError::new(UnknownFunction, "\{name} is unknown")
            }
          }
          match rv {
            JumpTo(target) => Some(target)
            Push(rv) => {
              stack.drop_top(args.length())
              stack.push(rv)
              None
            }
          }
        }
        CallMethod(name, arg_count) => {
          let args = stack.get_call_args(arg_count)
          let rv = args[0].call_method(
            state,
            name,
            args[1:args.length()].to_owned(),
          )
          stack.drop_top(args.length())
          stack.push(rv)
          None
        }
        CallObject(arg_count) => {
          let args = stack.get_call_args(arg_count)
          let rv = args[0].call(state, args[1:args.length()].to_owned())
          stack.drop_top(args.length())
          stack.push(rv)
          None
        }
        DupTop => {
          stack.push(stack.peek())
          None
        }
        DiscardTop => {
          stack.pop() |> ignore
          None
        }
        FastSuper => {
          perform_super(state, out, false) |> ignore
          None
        }
        FastRecurse =>
          match state.ctx.current_loop() {
            Some(l) => {
              guard l.object.recurse_jump_target is Some(target) else {
                raise TemplateError::new(
                  InvalidOperation,
                  "cannot recurse outside of recursive loop",
                )
              }
              next_loop_recursion_jump = Some((pc + 1, false))
              Some(target)
            }
            None => raise TemplateError::new(UnknownFunction, "loop is unknown")
          }
        // Explanation on the behavior of `LoadBlocks` and rendering of
        // inherited templates:
        //
        // MiniJinja inherits the behavior from Jinja2 where extending loads
        // the blocks (`LoadBlocks`) and the rest of the template keeps
        // executing but with output disabled, only at the end the parent
        // template is then invoked.  This has the effect that you can still
        // set variables or declare macros and that they become visible in
        // the blocks.
        LoadBlocks => {
          let a = stack.pop()
          if parent_instructions is Some(_) {
            raise TemplateError::new(
              InvalidOperation,
              "tried to extend a second time in a template",
            )
          }
          parent_instructions = Some(load_blocks(a, state))
          out.begin_capture(Discard)
          None
        }
        Include(ignore_missing) => {
          let a = stack.pop()
          perform_include(a, state, out, ignore_missing)
          None
        }
        ExportLocals => {
          let captured = stack.pop()
          let locals = state.ctx.current_locals()
          let values : Map[Value, Value] = Map([])
          // locals are a BTreeMap in MiniJinja, so exports are sorted
          for key in sorted_keys(locals) {
            values[Value::from_string(key)] = locals[key]
          }
          stack.push(Value::from_object(ModuleObject::{ values, captured, }))
          None
        }
        CallBlock(name) => {
          if parent_instructions is None && !out.is_discarding() {
            call_block(name, state, out) |> ignore
          }
          None
        }
        BuildMacro(name, offset, flags) => {
          build_macro(stack, state, offset, name, flags)
          None
        }
        Return => Some(-1)
        Enclose(name) => {
          // The first enclosed value creates a state-owned closure shared by
          // all macros declared in this frame.
          if state.ctx.closure() is None {
            state.ctx.reset_closure(Some({ values: Map([]), }))
          }
          state.ctx.enclose(name)
          None
        }
        GetClosure => {
          stack.push(
            match state.ctx.closure() {
              Some(closure) => Object(DynObject::new(ClosureRef(closure)))
              None => Value::undefined()
            },
          )
          None
        }
      }
    } catch {
      err => {
        process_err(err, pc, state)
        raise err
      }
    }
    match jump {
      Some(-1) => break // Return
      Some(target) => pc = target
      None => pc += 1
    }
  }
  stack.try_pop()
}

///|
priv enum CallResult {
  JumpTo(Int)
  Push(Value)
}

///|
fn return_jump(target : Int) -> CallResult {
  JumpTo(target)
}

///|
fn binop(
  stack : Stack,
  f : (Value, Value) -> Value raise TemplateError,
) -> Int? raise TemplateError {
  let b = stack.pop()
  let a = stack.pop()
  stack.push(f(a, b))
  None
}

///|
fn cmp_binop(
  stack : Stack,
  undefined_behavior : UndefinedBehavior,
  f : (Value, Value) -> Bool,
) -> Int? raise TemplateError {
  let b = stack.pop()
  let a = stack.pop()
  undefined_behavior.assert_value_not_undefined(a)
  undefined_behavior.assert_value_not_undefined(b)
  stack.push(Value::from_bool(f(a, b)))
  None
}

///|
fn merge_kwargs(
  state : State,
  values : Array[Value],
) -> Value raise TemplateError {
  let rv : Map[Value, Value] = Map([])
  for value in values {
    state.undefined_behavior().assert_iterable(value)
    let iter = match value {
      Object(obj) if obj.repr() is Map =>
        match obj.try_iter_pairs() {
          Some(iter) => iter
          None =>
            raise TemplateError::new(
              InvalidOperation,
              "attempted to apply keyword arguments from non map (got \{value.kind()})",
            )
        }
      _ =>
        raise TemplateError::new(
          InvalidOperation,
          "attempted to apply keyword arguments from non map (got \{value.kind()})",
        )
    }
    for pair in iter {
      rv[pair.0] = pair.1
    }
  }
  Value::from_kwargs_map(rv)
}

///|
fn perform_include(
  name : Value,
  state : State,
  out : Output,
  ignore_missing : Bool,
) -> Unit raise TemplateError {
  // candidates are consumed lazily: iteration stops at the first template
  // that exists (the value might be a one-shot iterator).
  let choices : Iter[Value] = match name {
    Object(obj) =>
      match obj.try_iter() {
        Some(iter) => iter
        None => Iter::empty()
      }
    _ => Iter::singleton(name)
  }
  let templates_tried = []
  for choice in choices {
    guard choice.as_str() is Some(name) else {
      raise TemplateError::new(
        InvalidOperation,
        "template name was not a string",
      )
    }
    let tmpl = state.get_template(name) catch {
      err => {
        if err.kind() == TemplateNotFound {
          templates_tried.push(choice)
        } else {
          raise err
        }
        continue
      }
    }
    let compiled = tmpl.compiled
    state.ctx.incr_depth(include_recursion_cost)
    let current_block = state.current_block
    let old_closure = state.ctx.take_closure()
    let rv = try {
      state.with_execution_state(
        compiled.instructions,
        compiled.initial_auto_escape,
        current_block,
        Replace(prepare_blocks(compiled.blocks)),
        state => eval_state(state, out),
      )
      |> ignore
      Ok(())
    } catch {
      err => Err(err)
    }
    state.ctx.reset_closure(old_closure)
    state.ctx.decr_depth(include_recursion_cost)
    if rv is Err(err) {
      raise TemplateError::new(BadInclude, "error in \"\{tmpl.name()}\"").with_source(
        err,
      )
    }
    return
  }
  if !templates_tried.is_empty() && !ignore_missing {
    raise TemplateError::new(
      TemplateNotFound,
      if templates_tried.length() == 1 {
        "tried to include non-existing template \{templates_tried[0].debug_string()}"
      } else {
        "tried to include one of multiple templates, none of which existed \{Value::from_array(templates_tried)}"
      },
    )
  }
}

///|
fn perform_super(
  state : State,
  out : Output,
  capture : Bool,
) -> CallResult raise TemplateError {
  guard state.current_block is Some(name) else {
    raise TemplateError::new(InvalidOperation, "cannot super outside of block")
  }
  guard state.blocks.get(name) is Some(block_stack) else {
    raise TemplateError::new(InvalidOperation, "no parent block exists")
  }
  if !block_stack.push() {
    raise TemplateError::new(InvalidOperation, "no parent block exists")
  }
  {
    errdefer block_stack.pop()
    state.ctx.push_frame(Frame::default())
  }
  if capture {
    out.begin_capture(Capture)
  }
  let instructions = block_stack.instructions()
  let auto_escape = state.auto_escape
  let current_block = state.current_block
  let rv = try {
    state.with_execution_state(instructions, auto_escape, current_block, Keep, state => {
      eval_state(state, out)
    })
    |> ignore
    Ok(())
  } catch {
    err => Err(err)
  }
  state.ctx.pop_frame() |> ignore
  block_stack.pop()
  if rv is Err(err) {
    raise TemplateError::new(EvalBlock, "error in super block").with_source(err)
  }
  if capture {
    Push(out.end_capture(state.auto_escape))
  } else {
    Push(Value::undefined())
  }
}

///|
fn load_blocks(name : Value, state : State) -> Instructions raise TemplateError {
  guard name.as_str() is Some(name) else {
    raise TemplateError::new(InvalidOperation, "template name was not a string")
  }
  if state.loaded_templates.contains(name) {
    raise TemplateError::new(
      InvalidOperation,
      "cycle in template inheritance. \{@rfmt.str_debug(name)} was referenced more than once",
    )
  }
  let tmpl = state.get_template(name)
  let compiled = tmpl.compiled
  state.loaded_templates.add(compiled.instructions.name)
  for block_name, instr in compiled.blocks {
    match state.blocks.get(block_name) {
      Some(stack) => stack.instructions.push(instr)
      None => state.blocks[block_name] = { instructions: [instr], depth: 0, }
    }
  }
  compiled.instructions
}

///|
fn call_block(
  name : String,
  state : State,
  out : Output,
) -> Value? raise TemplateError {
  guard state.blocks.get(name) is Some(block_stack) else {
    raise TemplateError::new(UnknownBlock, "block '\{name}' not found")
  }
  if block_stack.instructions.length() == 1 &&
    block_stack.instructions().required_block {
    raise TemplateError::new(
      InvalidOperation,
      "Required block '\{name}' not found",
    )
  }
  let instructions = block_stack.instructions()
  let auto_escape = state.auto_escape
  state.with_execution_state(instructions, auto_escape, Some(name), Keep, state => {
    state.ctx.push_frame(Frame::default())
    eval_state(state, out)
  })
}

///|
fn derive_auto_escape(
  value : Value,
  initial_auto_escape : AutoEscape,
) -> AutoEscape raise TemplateError {
  match (value.as_str(), value == Value::from_bool(true)) {
    (Some("html"), _) => Html
    (Some("json"), _) => Json
    (Some("none"), _) | (None, false) => NoEscape
    (None, true) =>
      if initial_auto_escape is NoEscape {
        Html
      } else {
        initial_auto_escape
      }
    _ =>
      raise TemplateError::new(
        InvalidOperation,
        "invalid value to autoescape tag",
      )
  }
}

///|
fn push_loop(
  state : State,
  iterable : Value,
  flags : Int,
  pc : Int,
  current_recursion_jump : (Int, Bool)?,
) -> Unit raise TemplateError {
  let iter = state.undefined_behavior().try_iter(iterable) catch {
      err =>
        match current_recursion_jump {
          Some((jump_instr, _)) => {
            // When a recursion error happens, we need to process the error at
            // both the recursion call site and the loop definition.
            process_err(err, pc, state)
            let call_err = TemplateError::new(
              InvalidOperation,
              "cannot recurse because of non-iterable value",
            )
            process_err(call_err, jump_instr - 1, state)
            raise call_err.with_source(err)
          }
          None => raise err
        }
    }
  let depth = match state.ctx.current_loop() {
    Some(l) if l.object.recurse_jump_target is Some(_) => l.object.depth + 1
    _ => 0
  }
  state.ctx.push_frame({
    ..Frame::default(),
    current_loop: Some(
      LoopState::new(
        iter,
        depth,
        (flags & LOOP_FLAG_WITH_LOOP_VAR) != 0,
        if (flags & LOOP_FLAG_RECURSIVE) != 0 {
          Some(pc)
        } else {
          None
        },
        current_recursion_jump,
      ),
    ),
  })
}

///|
fn unpack_list(stack : Stack, count : Int) -> Unit raise TemplateError {
  let top = stack.pop()
  let iter = match top {
    Object(obj) =>
      match obj.try_iter() {
        Some(iter) => iter
        None => raise TemplateError::new(CannotUnpack, "value is not iterable")
      }
    _ => raise TemplateError::new(CannotUnpack, "value is not iterable")
  }
  let mut n = 0
  for item in iter {
    stack.push(item)
    n += 1
  }
  if n == count {
    stack.reverse_top(n)
  } else {
    raise TemplateError::new(
      CannotUnpack,
      "sequence of wrong length (expected \{count}, got \{n})",
    )
  }
}

///|
fn build_macro(
  stack : Stack,
  state : State,
  offset : Int,
  name : String,
  flags : Int,
) -> Unit raise TemplateError {
  let arg_spec = stack.pop().try_iter().to_array()
  let closure = match stack.pop() {
    Object({ inner: ClosureRef(c), .. }) => Some(c)
    _ => None
  }
  stack.push(
    Value::from_object(MacroObject::{
      name: Value::from_string(name),
      arg_spec,
      instructions: state.instructions,
      offset,
      state_id: state.id,
      closure,
      caller_reference: (flags & MACRO_CALLER) != 0,
    }),
  )
}

///|
fn process_err(err : TemplateError, pc : Int, state : State) -> Unit {
  // only attach line information if the error does not have line info yet.
  if err.line() is None {
    match state.instructions.get_span(pc) {
      Some(span) => err.set_filename_and_span(state.instructions.name, span)
      None =>
        if state.instructions.get_line(pc) is Some(lineno) {
          err.set_filename_and_line(state.instructions.name, lineno)
        }
    }
  }
  // only attach debug info if we don't have one yet and we are in debug
  // mode.
  if state.env().debug && err.debug_info() is None {
    err.attach_debug_info(state.make_debug_info(pc, state.instructions))
  }
}
