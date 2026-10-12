# Биндинги CPython C API (libpython), как ext/pycall/libpython.c в гемме.
#
# Оригинал грузит libpython через dlopen в рантайме; порт линкуется
# компиляции-time (см. PLAN.md «Отклонения»).

@[Link("python3.13")]
lib LibPy
  alias PyObjectT = Void

  # --- инициализация и GIL -------------------------------------------------
  fun py_initialize = Py_Initialize
  fun py_is_initialized = Py_IsInitialized : Int32
  fun py_gil_state_ensure = PyGILState_Ensure : Int32
  fun py_gil_state_release = PyGILState_Release(gilstate : Int32)
  fun py_gil_state_check = PyGILState_Check : Int32
  fun py_eval_save_thread = PyEval_SaveThread : Void*

  # --- refcounting ----------------------------------------------------------
  fun py_incref = Py_IncRef(o : PyObjectT*)
  fun py_decref = Py_DecRef(o : PyObjectT*)

  fun py_get_version = Py_GetVersion : UInt8*

  # --- импорт ----------------------------------------------------------------
  fun py_import_import_module = PyImport_ImportModule(name : UInt8*) : PyObjectT*
  fun py_import_add_module = PyImport_AddModule(name : UInt8*) : PyObjectT*

  # --- атрибуты --------------------------------------------------------------
  fun py_object_get_attr_string = PyObject_GetAttrString(o : PyObjectT*, name : UInt8*) : PyObjectT*
  fun py_object_set_attr_string = PyObject_SetAttrString(o : PyObjectT*, name : UInt8*, value : PyObjectT*) : Int32
  fun py_object_has_attr_string = PyObject_HasAttrString(o : PyObjectT*, name : UInt8*) : Int32
  fun py_object_del_attr_string = PyObject_DelAttrString(o : PyObjectT*, name : UInt8*) : Int32

  # --- вызов ------------------------------------------------------------------
  fun py_object_call = PyObject_Call(callable : PyObjectT*, args : PyObjectT*, kwargs : PyObjectT*) : PyObjectT*
  fun py_callable_check = PyCallable_Check(o : PyObjectT*) : Int32

  # --- элементы контейнеров ----------------------------------------------------
  fun py_object_get_item = PyObject_GetItem(o : PyObjectT*, key : PyObjectT*) : PyObjectT*
  fun py_object_set_item = PyObject_SetItem(o : PyObjectT*, key : PyObjectT*, value : PyObjectT*) : Int32
  fun py_object_del_item = PyObject_DelItem(o : PyObjectT*, key : PyObjectT*) : Int32

  # --- строковое представление / сравнение -------------------------------------
  fun py_object_str = PyObject_Str(o : PyObjectT*) : PyObjectT*
  fun py_object_repr = PyObject_Repr(o : PyObjectT*) : PyObjectT*
  fun py_object_rich_compare = PyObject_RichCompare(a : PyObjectT*, b : PyObjectT*, op : Int32) : PyObjectT*
  fun py_object_is_true = PyObject_IsTrue(o : PyObjectT*) : Int32
  fun py_object_dir = PyObject_Dir(o : PyObjectT*) : PyObjectT*

  # --- итерация -----------------------------------------------------------------
  fun py_object_get_iter = PyObject_GetIter(o : PyObjectT*) : PyObjectT*
  fun py_iter_next = PyIter_Next(o : PyObjectT*) : PyObjectT*

  # --- числа ----------------------------------------------------------------------
  fun py_bool_from_long = PyBool_FromLong(v : Int32) : PyObjectT*
  fun py_long_from_long_long = PyLong_FromLongLong(v : Int64) : PyObjectT*
  fun py_long_as_long_long = PyLong_AsLongLong(o : PyObjectT*) : Int64
  fun py_float_from_double = PyFloat_FromDouble(v : Float64) : PyObjectT*
  fun py_float_as_double = PyFloat_AsDouble(o : PyObjectT*) : Float64
  fun py_number_long = PyNumber_Long(o : PyObjectT*) : PyObjectT*
  fun py_number_float = PyNumber_Float(o : PyObjectT*) : PyObjectT*

  # --- unicode -----------------------------------------------------------------------
  fun py_unicode_from_string = PyUnicode_FromString(utf8 : UInt8*) : PyObjectT*
  fun py_unicode_as_utf8 = PyUnicode_AsUTF8(o : PyObjectT*) : UInt8*

  # --- tuple ---------------------------------------------------------------------------
  fun py_tuple_new = PyTuple_New(size : Int64) : PyObjectT*
  fun py_tuple_size = PyTuple_Size(o : PyObjectT*) : Int64
  fun py_tuple_get_item = PyTuple_GetItem(o : PyObjectT*, i : Int64) : PyObjectT*
  fun py_tuple_set_item = PyTuple_SetItem(o : PyObjectT*, i : Int64, v : PyObjectT*) : Int32

  # --- list ----------------------------------------------------------------------------
  fun py_list_new = PyList_New(size : Int64) : PyObjectT*
  fun py_list_size = PyList_Size(o : PyObjectT*) : Int64
  fun py_list_get_item = PyList_GetItem(o : PyObjectT*, i : Int64) : PyObjectT*
  fun py_list_set_item = PyList_SetItem(o : PyObjectT*, i : Int64, v : PyObjectT*) : Int32
  fun py_list_append = PyList_Append(o : PyObjectT*, v : PyObjectT*) : Int32

  # --- dict ----------------------------------------------------------------------------
  fun py_dict_new = PyDict_New : PyObjectT*
  fun py_dict_size = PyDict_Size(o : PyObjectT*) : Int64
  fun py_dict_set_item = PyDict_SetItem(o : PyObjectT*, key : PyObjectT*, value : PyObjectT*) : Int32
  fun py_dict_get_item_with_error = PyDict_GetItemWithError(o : PyObjectT*, key : PyObjectT*) : PyObjectT*
  fun py_dict_contains = PyDict_Contains(o : PyObjectT*, key : PyObjectT*) : Int32
  fun py_dict_del_item = PyDict_DelItem(o : PyObjectT*, key : PyObjectT*) : Int32
  fun py_dict_next = PyDict_Next(o : PyObjectT*, pos : Int64*, key : PyObjectT**, value : PyObjectT**) : Int32

  # --- sequence / set -------------------------------------------------------------------
  fun py_sequence_contains = PySequence_Contains(o : PyObjectT*, v : PyObjectT*) : Int32
  fun py_set_size = PySet_Size(o : PyObjectT*) : Int64
  fun py_set_contains = PySet_Contains(o : PyObjectT*, v : PyObjectT*) : Int32

  # --- slice -----------------------------------------------------------------------------
  fun py_slice_new = PySlice_New(start : PyObjectT*, stop : PyObjectT*, step : PyObjectT*) : PyObjectT*

  # --- ошибки -----------------------------------------------------------------------------
  fun py_err_occurred = PyErr_Occurred : PyObjectT*
  fun py_err_clear = PyErr_Clear
  fun py_err_fetch = PyErr_Fetch(type : PyObjectT**, value : PyObjectT**, traceback : PyObjectT**)
  fun py_err_normalize_exception = PyErr_NormalizeException(type : PyObjectT**, value : PyObjectT**, traceback : PyObjectT**)
  fun py_err_set_string = PyErr_SetString(exc : PyObjectT*, msg : UInt8*)
  fun py_err_exception_matches = PyErr_ExceptionMatches(exc : PyObjectT*) : Int32

  # --- колбэки (Proc → python callable) ----------------------------------------------------
  fun py_cfunction_new_ex = PyCFunction_NewEx(ml : PyMethodDef*, self : PyObjectT*, module : PyObjectT*) : PyObjectT*
  fun py_capsule_new = PyCapsule_New(pointer : Void*, name : UInt8*, destructor : (Void*) ->) : PyObjectT*
  fun py_capsule_get_pointer = PyCapsule_GetPointer(capsule : PyObjectT*, name : UInt8*) : Void*

  # Определение PyObject: заголовок (refcnt, ob_type) — как pyobject_struct.rb в гемме.
  struct PyObjectHeader
    ob_refcnt : Int64
    ob_type : PyObjectT*
  end

  struct PyMethodDef
    ml_name : UInt8*
    ml_meth : (PyObjectT*, PyObjectT*) -> PyObjectT*
    ml_flags : Int32
    ml_doc : UInt8*
  end

  # Синглтоны/типы — В C это макросы вида `#define Py_None (&_Py_NoneStruct)`,
  # поэтому биндим поле по адресу (важен только адрес) и берём pointerof.
  $py_none_struct = _Py_NoneStruct : UInt8
  $py_true_struct = _Py_TrueStruct : UInt8
  $py_false_struct = _Py_FalseStruct : UInt8
  $py_bool_type = PyBool_Type : UInt8
  $py_long_type = PyLong_Type : UInt8
  $py_float_type = PyFloat_Type : UInt8
  $py_unicode_type = PyUnicode_Type : UInt8
  $py_list_type = PyList_Type : UInt8
  $py_dict_type = PyDict_Type : UInt8
  $py_tuple_type = PyTuple_Type : UInt8
  $py_set_type = PySet_Type : UInt8
  $py_type_type = PyType_Type : UInt8
  $py_exc_runtime_error = PyExc_RuntimeError : PyObjectT*
  $py_exc_stop_iteration = PyExc_StopIteration : PyObjectT*
end

# Обёртки над libpython (аналог LibPython::Helpers + LibPython::API в гемме).
module PyCall
  module LibPython
    # Боги rich-compare из CPython (object.h).
    OP_LT = 0
    OP_LE = 1
    OP_EQ = 2
    OP_NE = 3
    OP_GT = 4
    OP_GE = 5

    METH_VARARGS = 0x0001

    def self.none : LibPy::PyObjectT*
      pointerof(LibPy.py_none_struct).as(LibPy::PyObjectT*)
    end

    def self.py_true : LibPy::PyObjectT*
      pointerof(LibPy.py_true_struct).as(LibPy::PyObjectT*)
    end

    def self.py_false : LibPy::PyObjectT*
      pointerof(LibPy.py_false_struct).as(LibPy::PyObjectT*)
    end

    {% for t in %w(bool long float unicode list dict tuple set type) %}
      def self.py_{{t.id}}_type : LibPy::PyObjectT*
        pointerof(LibPy.py_{{t.id}}_type).as(LibPy::PyObjectT*)
      end
    {% end %}

    def self.type_of(o : LibPy::PyObjectT*) : LibPy::PyObjectT*
      o.as(LibPy::PyObjectHeader*).value.ob_type
    end

    # Вызывается под взятым GIL; null-результат с выставленной ошибкой → PyError.
    def self.check!(result : LibPy::PyObjectT*, context : String) : LibPy::PyObjectT*
      return result unless result.null?
      if !LibPy.py_err_occurred.null?
        PyError.fetch_and_raise(context)
      end
      raise Error.new("#{context} returned NULL without error set")
    end

    def self.check_status(status : Int32, context : String) : Nil
      return if status >= 0
      PyError.fetch_and_raise(context) unless LibPy.py_err_occurred.null?
      raise Error.new("#{context} failed")
    end

    def self.import_module(name : String) : LibPy::PyObjectT*
      PyCall.gil { check!(LibPy.py_import_import_module(name), "PyImport_ImportModule(#{name})") }
    end

    def self.getattr(o : LibPy::PyObjectT*, name : String) : LibPy::PyObjectT*
      PyCall.gil { check!(LibPy.py_object_get_attr_string(o, name), "PyObject_GetAttrString(#{name})") }
    end

    def self.hasattr?(o : LibPy::PyObjectT*, name : String) : Bool
      PyCall.gil { LibPy.py_object_has_attr_string(o, name) != 0 }
    end

    def self.setattr(o : LibPy::PyObjectT*, name : String, value : LibPy::PyObjectT*) : Nil
      PyCall.gil do
        check_status(LibPy.py_object_set_attr_string(o, name, value), "PyObject_SetAttrString(#{name})")
      end
    end

    def self.delattr(o : LibPy::PyObjectT*, name : String) : Nil
      PyCall.gil do
        check_status(LibPy.py_object_del_attr_string(o, name), "PyObject_DelAttrString(#{name})")
      end
    end

    def self.call_object(f : LibPy::PyObjectT*, args, kwargs : LibPy::PyObjectT* | Nil = nil) : LibPy::PyObjectT*
      PyCall.gil do
        tuple = LibPy.py_tuple_new(args.size)
        raise Error.new("PyTuple_New failed") if tuple.null?
        args.each_with_index do |arg, i|
          item = Conversion.from_crystal(arg)
          LibPy.py_tuple_set_item(tuple, i, item) # steals item
        end
        kw = kwargs.nil? ? Pointer(Void).null : kwargs
        result = LibPy.py_object_call(f, tuple, kw)
        LibPy.py_decref(tuple)
        check!(result, "PyObject_Call")
      end
    end

    def self.getitem(o : LibPy::PyObjectT*, key) : LibPy::PyObjectT*
      PyCall.gil do
        k = Conversion.from_crystal(key)
        result = LibPy.py_object_get_item(o, k)
        LibPy.py_decref(k)
        check!(result, "PyObject_GetItem")
      end
    end

    def self.setitem(o : LibPy::PyObjectT*, key, value) : Nil
      PyCall.gil do
        k = Conversion.from_crystal(key)
        v = Conversion.from_crystal(value)
        status = LibPy.py_object_set_item(o, k, v)
        LibPy.py_decref(k)
        LibPy.py_decref(v)
        check_status(status, "PyObject_SetItem")
      end
    end

    def self.delitem(o : LibPy::PyObjectT*, key) : Nil
      PyCall.gil do
        k = Conversion.from_crystal(key)
        status = LibPy.py_object_del_item(o, k)
        LibPy.py_decref(k)
        check_status(status, "PyObject_DelItem")
      end
    end

    def self.str(o : LibPy::PyObjectT*) : String
      PyCall.gil do
        s = check!(LibPy.py_object_str(o), "PyObject_Str")
        copy = String.new(LibPy.py_unicode_as_utf8(s))
        LibPy.py_decref(s)
        copy
      end
    end

    def self.repr(o : LibPy::PyObjectT*) : String
      PyCall.gil do
        s = check!(LibPy.py_object_repr(o), "PyObject_Repr")
        copy = String.new(LibPy.py_unicode_as_utf8(s))
        LibPy.py_decref(s)
        copy
      end
    end

    def self.compare(op : Int32, a : LibPy::PyObjectT*, b : LibPy::PyObjectT*) : Bool
      PyCall.gil do
        result = check!(LibPy.py_object_rich_compare(a, b, op), "PyObject_RichCompare")
        truthy = LibPy.py_object_is_true(result)
        LibPy.py_decref(result)
        raise Error.new("PyObject_IsTrue failed") if truthy < 0
        truthy == 1
      end
    end

    def self.callable?(o : LibPy::PyObjectT*) : Bool
      PyCall.gil { LibPy.py_callable_check(o) != 0 }
    end
  end
end
