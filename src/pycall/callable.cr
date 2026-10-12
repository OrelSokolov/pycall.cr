# PyCall::Callable — Proc → python callable. Порт libffi-части гема
# (pycall_ruby_wrapper): вместо libffi-трамплинов — PyCFunction_NewEx
# с нетипизированным трамплином + PyCapsule-ключ в registry.

module PyCall
  class Callable < PyWrap
    @@registry = {} of Void* => Proc(Array(PyValue), PyValue)
    @@counter = Atomic(UInt64).new(0)

    # Публичный конструктор с блоком — аналог передачи блока в гемме.
    def self.new(name : String = "pycall_callback", &blk : Array(PyValue) -> PyValue) : Callable
      new(->(cb_args : Array(PyValue)) : PyValue { blk.call(cb_args) }, name)
    end

    def initialize(@key : Void*, ptr : LibPy::PyObjectT*)
      super(ptr) # steals
    end

    def self.new(proc : Proc(Array(PyValue), PyValue), name : String = "pycall_callback")
      PyCall.gil do
        key = Pointer(Void).malloc(1).as(Void*) # уникальный адрес-ключ
        capsule = LibPy.py_capsule_new(
          key,
          "pycall.callable",
          ->Callable.destructor(Void*))
        LibPython.check!(capsule, "PyCapsule_New")

        # PyMethodDef должен жить пока жив CFunction — держим в heap
        def_ptr = Pointer(LibPy::PyMethodDef).malloc(1)
        def_ptr.value.ml_name = name.to_unsafe
        def_ptr.value.ml_meth = ->Callable.trampoline(LibPy::PyObjectT*, LibPy::PyObjectT*)
        def_ptr.value.ml_flags = LibPython::METH_VARARGS
        def_ptr.value.ml_doc = Pointer(UInt8).null

        obj = LibPy.py_cfunction_new_ex(def_ptr, capsule, nil)
        LibPy.py_decref(capsule) # new_ex держит свою ссылку
        LibPython.check!(obj, "PyCFunction_NewEx")

        @@registry[key] = proc
        inst = allocate.as(Callable)
        inst.initialize(key, obj) # steals obj
        inst
      end
    end

    def finalize
      @@registry.delete(@key) unless @key.null?
      PyCall.gil { LibPy.py_decref(__pyptr__) }
    rescue
    end

    def self.destructor(capsule : Void*)
      # python вызывает при уничтожении capsule; registry чистится в finalize
    end

    # Трамплин: python уже держит GIL при вызове сюда.
    def self.trampoline(self_p : LibPy::PyObjectT*, args_p : LibPy::PyObjectT*) : LibPy::PyObjectT*
      key = LibPy.py_capsule_get_pointer(self_p, "pycall.callable")
      proc = @@registry[key]?
      if proc.nil?
        LibPy.py_err_set_string(LibPy.py_exc_runtime_error, "pycall: lost callback registry entry")
        return Pointer(Void).null.as(LibPy::PyObjectT*)
      end

      args = Array(PyValue).new(LibPy.py_tuple_size(args_p)) do |i|
        Conversion.to_crystal_borrowed(LibPy.py_tuple_get_item(args_p, i))
      end

      result = begin
        proc.call(args)
      rescue ex
        LibPy.py_err_set_string(LibPy.py_exc_runtime_error, "pycall callback raised: #{ex.message}".to_unsafe)
        return Pointer(Void).null.as(LibPy::PyObjectT*)
      end

      Conversion.from_crystal(result)
    end
  end
end
