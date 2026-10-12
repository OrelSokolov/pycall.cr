# pycall_cr — порт гема pycall (mrkn/pycall) на Crystal.
# Точка входа: require "pycall_cr" → PyCall.import_module("math").pi

require "./pycall/types"
require "./pycall/libpython"
require "./pycall/pyerror"
require "./pycall/conversion"
require "./pycall/pyobject_wrapper"
require "./pycall/callable"
require "./pycall/list"
require "./pycall/dict"
require "./pycall/tuple"
require "./pycall/set"
require "./pycall/iterable_wrapper"
require "./pycall/import"

module PyCall
  VERSION = "0.1.0"

  # Глобальная блокировка на ВЕСЬ доступ к Python из Crystal.
  #
  # CPython GIL (PyGILState_Ensure/Release) защищает отдельные C-вызовы,
  # но составные операции (getattr → call → convert, обход dict и т.п.)
  # без неё могли чередоваться между фиберами на разных тредах.
  # Этот мьютекс сериализует операции целиком — один глобальный замок
  # на весь шард, как require GVL в MRI.
  #
  # Вложенные вызовы PyCall.gil на том же треде идут по быстрому пути:
  # если тред уже держит GIL (внешний захват или трамплин колбэка),
  # повторный захват мьютекса не выполняется — иначе нереентерабельный
  # Mutex дал бы дедлок. Порядок проверок критичен: колбэк из Python
  # (трамплин) держит GIL, НЕ держит мьютекс — и не должен его брать,
  # пока другой тред ждёт GIL под мьютексом.
  MUTEX = Mutex.new

  @@initialized = false
  @@builtins : PyWrap?
  @@sys : PyWrap?
  @@main_dict : PyWrap?

  # Инициализация интерпретатора — PyCall.init в гемме.
  # Идемпотентна; вызывается автоматически при первом обращении к API.
  def self.init! : Bool
    return false if @@initialized
    MUTEX.synchronize do
      return false if @@initialized
      LibPy.py_initialize
      # Отдаём GIL инициализирующего треда: дальше каждый вызов берёт GIL
      # через PyGILState_Ensure (кристалловские фиберы живут на N тредах).
      LibPy.py_eval_save_thread
      @@initialized = true
    end
    true
  end

  def self.initialized? : Bool
    @@initialized
  end

  def self.ensure_init! : Nil
    init! unless @@initialized
  end

  # Взять GIL на блок (PyGILState_Ensure/Release) под глобальным мьютексом.
  # Реентерабелен на том же треде (см. комментарий у MUTEX).
  def self.gil
    # Py_Initialize обязан случиться до любого PyGILState_*/Py*-вызова:
    # раньше сюда можно было попасть до инициализации (например, eval →
    # main_dict) — PyGILState_Ensure на неинициализированном интерпретаторе
    # даёт UB и сегфолт глубоко внутри CPython.
    ensure_init!
    if LibPy.py_gil_state_check != 0
      # Тред уже держит GIL: либо наш внешний PyCall.gil (держим и мьютекс),
      # либо трамплин колбэка из Python — мьютекс брать нельзя (дедлок).
      yield
    else
      MUTEX.synchronize do
        state = LibPy.py_gil_state_ensure
        begin
          yield
        ensure
          LibPy.py_gil_state_release(state)
        end
      end
    end
  end

  # "3.13.7 (v3.13.7:...) [GCC ...]" → "3.13.7"
  def self.python_version : String
    ensure_init!
    PyCall.gil { String.new(LibPy.py_get_version).split(' ').first }
  end

  def self.python_description : String
    ensure_init!
    PyCall.gil { String.new(LibPy.py_get_version) }
  end

  def self.builtins : PyWrap
    @@builtins ||= begin
      ensure_init!
      PyWrap.wrap(LibPython.import_module("builtins"))
    end
  end

  def self.sys : PyWrap
    @@sys ||= import_module("sys")
  end

  def self.import_module(name : String | Symbol) : PyWrap
    ensure_init!
    PyWrap.wrap(LibPython.import_module(name.to_s))
  end

  # globals для eval/exec — __dict__ модуля __main__ (как в гемме).
  private def self.main_dict : PyWrap
    @@main_dict ||= begin
      main = PyCall.gil do
        m = LibPy.py_import_add_module("__main__") # borrowed
        raise Error.new("PyImport_AddModule(__main__) failed") if m.null?
        m
      end
      PyWrap.wrap(LibPython.getattr(main, "__dict__"))
    end
  end

  def self.eval(expr : String, globals : PyWrap? = nil, locals : PyWrap? = nil) : Object
    g = globals || main_dict
    if locals
      builtins.__call_attr("eval", expr, g, locals)
    else
      builtins.__call_attr("eval", expr, g)
    end
  end

  def self.exec(code : String, globals : PyWrap? = nil, locals : PyWrap? = nil) : Nil
    g = globals || main_dict
    if locals
      builtins.__call_attr("exec", code, g, locals)
    else
      builtins.__call_attr("exec", code, g)
    end
    nil
  end

  def self.getattr(obj : PyWrap, name : String) : Object
    obj.__getattr_or_call0(name)
  end

  def self.hasattr?(obj : PyWrap, name : String) : Bool
    LibPython.hasattr?(obj.__pyptr__, name)
  end

  def self.setattr(obj : PyWrap, name : String, value) : Object
    obj.__setattr(name, value)
  end

  def self.delattr(obj : PyWrap, name : String) : Nil
    LibPython.delattr(obj.__pyptr__, name)
  end

  def self.same?(left : PyWrap, right : PyWrap) : Bool
    left.__pyptr__ == right.__pyptr__
  end

  def self.len(obj : PyWrap) : Int64
    builtins.__call_attr("len", obj).as(Int64)
  end

  def self.dir(obj : PyWrap) : Object
    PyCall.gil { Conversion.to_crystal(LibPython.check!(LibPy.py_object_dir(obj.__pyptr__), "PyObject_Dir")) }
  end

  # Примитивы (конвертированные из Python) не-callable по определению.
  def self.callable?(obj : PyValue) : Bool
    case obj
    when PyWrap then builtins.__call_attr("callable", obj) == true
    else false
    end
  end

  # iterable может быть PyWrap или Crystal-значением (Array и т.п. —
  # конвертация через Conversion.from_crystal).
  def self.tuple(iterable = nil) : Tuple
    pyptr = if iterable
              builtins.__call_attr("tuple", iterable)
            else
              builtins.__call_attr("tuple")
            end
    raise Error.new("tuple() did not return a tuple") unless pyptr.is_a?(Tuple)
    pyptr
  end

  def self.iterable(obj : PyWrap) : IterableWrapper
    IterableWrapper.new(obj)
  end

  # Менеджер контекста: PyCall.with(open(...)) { |f| ... }
  def self.with(ctx : PyWrap)
    yielded = ctx.__getattr_or_call0("__enter__")
    begin
      yield yielded
    rescue err : PyError
      exit_val = ctx.__call_attr("__exit__", err.type, err.value, err.traceback)
      raise err unless PyCall.truthy?(exit_val)
    else
      ctx.__call_attr("__exit__", nil, nil, nil)
    end
  end

  def self.truthy?(obj : Object) : Bool
    case obj
    when Bool then obj
    when Nil then false
    when PyWrap
      LibPy.py_object_is_true(obj.__pyptr__) == 1
    else true
    end
  end

  # Обёртка Proc → python callable (см. PyCall::Callable).
  def self.callable(proc : Proc(Array(PyValue), PyValue), name : String = "pycall_callback") : Callable
    Callable.new(proc, name)
  end
end
