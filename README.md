# pycall.cr

A Crystal port of [mrkn/pycall](https://github.com/mrkn/pycall) — call
Python from Crystal through the **CPython C API** (libpython), with
reference counting, GIL management, typed wrappers for list/dict/tuple/
set, iteration, callbacks and full type conversion. Verified against
real Python 3.13.7 via an oracle. Suite: 19 examples, 0 failures.

## Installation

```yaml
dependencies:
  pycall_cr:
    github: OrelSokolov/pycall.cr
```

```sh
shards install
```

Requires `python3.13` with `libpython3.13.so` (compile-time linking via
`@[Link("python3.13")]`, unlike the gem's runtime `dlopen`).

## Usage

```crystal
require "pycall_cr"

include PyCall::Import
pyimport :math

PyCall.gil do
  np = PyCall.import_module("numpy")
  arr = np.arange(10)
  puts PyCall.len(arr)            # => 10
  puts arr.sum.as(PyCall::PyWrap) # operators need an explicit cast
end

builtins = PyCall.builtins
sorted = PyCall.eval("sorted")
list = PyCall::List.new([3, 1, 2])
sorted.call(list, key: PyCall::Callable.new { |args| args[0] })
```

See `examples/smoke.cr` for an end-to-end tour of the API.

## Feature comparison vs pycall (gem 1.6.x)

### Interpreter & modules

| Feature | Original (pycall) | Port (pycall.cr) | Status |
|---|---|---|---|
| `PyCall.init` / `PYTHON_VERSION` / `PYTHON_DESCRIPTION` | ✅ | `PyCall.init!`, `PyCall.python_version`, … | ✅ |
| `PyCall.import_module` → module wrapper | ✅ | → `PyWrap` | ✅ |
| `PyCall.builtins` / `PyCall.sys` (lazy, auto-init) | ✅ | Same | ✅ |
| `PyCall.eval` / `PyCall.exec` (via builtins, `__main__.__dict__`) | ✅ | Same | ✅ |
| `pyimport` / `pyfrom`, `include PyCall::Import` | ✅ | Same | ✅ |

### Objects, dispatch & operators

| Feature | Original | Port | Status |
|---|---|---|---|
| `method_missing`: getter / `name=` / call with args | ✅ (runtime) | `macro method_missing` (compile-time) + `__getattr_or_call0`; no runtime `send` | 🔶 |
| Attribute semantics (pycall.c:1209): non-callable → value; callable (non-type) → invoke | ✅ | Same 1:1 | ✅ |
| Operators `+ - * / % ** << >> & \| ^ ~ -@` → `__add__`… | ✅ | Same | ✅ |
| Comparisons via `PyObject_RichCompare` | ✅ | Same | ✅ |
| `[] / []=` (GetItem/SetItem, Range → slice) | ✅ | Same | ✅ |
| `call(*args)` (+ kwargs), `inspect/to_s/to_i/to_f/dup` | ✅ | Same | ✅ |
| `PyCall.len/dir/callable?/same?/tuple/iterable/with` | ✅ | Same | ✅ |
| `getattr/hasattr?/setattr/delattr` | ✅ | Same | ✅ |
| `coerce` / SwappedOperationAdapter (python object on the right of a primitive) | ✅ | Not portable (no coerce protocol) — use explicit `.call` | ❌ |

### Collections, iteration & errors

| Feature | Original | Port | Status |
|---|---|---|---|
| `List` (each/Enumerable, include?, length, `<<`/push, sort/sort!, to_a) | ✅ | `PyCall::List` | ✅ |
| `Dict` (has_key?, `[]` nil-safe, delete, each, to_h, length) | ✅ | `PyCall::Dict` | ✅ |
| `Tuple` / `Set` | ✅ | `PyCall::Tuple` / `PyCall::Set` | ✅ |
| `IterableWrapper` (GetIter/PyIter_Next, StopIteration) | ✅ | `PyCall::IterableWrapper` | ✅ |
| `PyError` (type/value/traceback, format_tb) | ✅ | `PyCall::PyError` | ✅ |

### Callbacks, conversion & threading

| Feature | Original | Port | Status |
|---|---|---|---|
| Ruby Proc/block → python callable (libffi) | ✅ | `PyCall::Callable` (PyCFunction + PyCapsule registry, no libffi); typed `&block : Array(PyValue) -> PyValue`, passed explicitly to `#call` or as a `Callable` kwarg | 🔶 |
| Conversion nil/bool/int/float/str/array/hash/range→slice/proc | ✅ | `Conversion.from_crystal/to_crystal`; values are a closed `PyValue` union (`Nil\|Bool\|Int64\|Float64\|String\|PyWrap`) — operators on results need `.as(PyCall::PyWrap)` | 🔶 |
| `register_python_type_mapping` | ✅ | Dispatch on `ob_type` in `PyWrap.wrap` | ✅ |
| GIL management (`PyGILState_Ensure/Release`) | ✅ | `PyCall.gil { }` — **mandatory**: fibers run on N threads; a global mutex serializes all Python access (nested `gil` takes a fast path) | ✅ |
| Linking | runtime `dlopen` of libpython | Compile-time linking (`-lpython3.13`) — same feature set | 🔶 |

## Deviations & Crystal-specific notes

- `PyCall::List` names the wrapper class (in the gem it is the python
  `list` type); the python type is `PyCall.eval("list")`.
- `Py_Initialize` must run before any GIL acquisition — `ensure_init!`
  is built into `PyCall.gil`, the single entry point.
- All `Py_IncRef`/`Py_DecRef` (including finalizers) happen under the
  GIL: fibers live on multiple threads and decref without the GIL
  crashes the interpreter.
- Spec includes concurrency tests: 8 fibers × 100 iterations and 4 fibers
  with callbacks.

## Testing

```sh
crystal spec                # needs python3.13 + libpython3.13.so
crystal run examples/smoke.cr
```

Oracle: values recorded with real Python 3.13.7 (`oracle/expected.yml`)
and replayed by the Crystal specs.
