# PyWrap — порт PyObjectWrapper (lib/pycall/pyobject_wrapper.rb +
# pycall_pyobject_wrapper_wrapper_method из ext/pycall/pycall.c).

module PyCall
  class PyWrap
    # Дуандеры для операторов, как OPERATOR_METHOD_NAMES в гемме.
    OPERATOR_NAMES = {
      "+":  "__add__",
      "-":  "__sub__",
      "*":  "__mul__",
      "/":  "__truediv__",
      "%":  "__mod__",
      "**": "__pow__",
      "<<": "__lshift__",
      ">>": "__rshift__",
      "&":  "__and__",
      "|":  "__or__",
      "^":  "__xor__",
    }

    @__pyptr__ : LibPy::PyObjectT*

    # Забирает (steals) переданную ссылку — как PyCall::PyPtr в гемме.
    def initialize(@__pyptr__ : LibPy::PyObjectT*)
      raise Error.new("cannot wrap NULL PyObject") if @__pyptr__.null?
    end

    def finalize
      PyCall.gil { LibPy.py_decref(@__pyptr__) }
    rescue
      # финалайзер не должен ронять программу (например, при выходе)
    end

    def __pyptr__ : LibPy::PyObjectT*
      @__pyptr__
    end

    def to_unsafe : LibPy::PyObjectT*
      @__pyptr__
    end

    # Диспетчеризация по ob_type — аналог register_python_type_mapping.
    def self.wrap(p : LibPy::PyObjectT*) : PyWrap
      case LibPython.type_of(p)
      when .==(LibPython.py_list_type) then List.new(p)
      when .==(LibPython.py_dict_type) then Dict.new(p)
      when .==(LibPython.py_tuple_type) then Tuple.new(p)
      when .==(LibPython.py_set_type) then Set.new(p)
      else PyWrap.new(p)
      end
    end

    # --- method_missing: семантика pycall (pycall.c:1209) -------------------
    # голый атрибут: не-callable → значение; callable (не тип) → вызвать;
    # `x = v` → setattr; `x(a, ...)` → вызвать с аргументами.
    # В Crystal method_missing — compile-time макрос: имена известны при
    # компиляции вызова (см. PLAN.md).

    macro method_missing(call)
      {% if call.name.id.stringify.ends_with?('=') && call.args.size == 1 && !call.named_args %}
        __setattr({{call.name.id.stringify}}, {{call.args.first}})
      {% elsif call.args.empty? && !call.named_args %}
        __getattr_or_call0({{call.name.id.stringify}})
      {% else %}
        __call_attr({{call.name.id.stringify}}{% for a in call.args %}, {{a}}{% end %}{% if call.named_args %}{% for na in call.named_args %}, {{na.name.id}}: {{na.value}}{% end %}{% end %})
      {% end %}
    end

    def __getattr_or_call0(name : String) : PyValue
      attr = LibPython.getattr(@__pyptr__, name)
      PyCall.gil do
        if LibPython.callable?(attr) && LibPython.type_of(attr) != LibPython.py_type_type
          result = LibPython.check!(LibPy.py_object_call(attr, LibPy.py_tuple_new(0), nil), "PyObject_Call(#{name})")
          LibPy.py_decref(attr)
          Conversion.to_crystal(result)
        else
          Conversion.to_crystal(attr)
        end
      end
    end

    # ВАЖНО: типизированный `&block` в Crystal делает блок обязательным —
    # вызов без блока уходил бы в method_missing. Поэтому две перегрузки.

    def __call_attr(name : String, *args, **kwargs) : PyValue
      # args — Tuple, пробрасываем как есть (impl принимает любой индексируемый
      # контейнер; несовпадение аннотаций уводило вызов в method_missing).
      __call_attr_impl(name, args, kwargs)
    end

    def __call_attr(name : String, *args, **kwargs, &block : Array(PyValue) -> PyValue) : PyValue
      cb = Callable.new(->(cb_args : Array(PyValue)) : PyValue { block.call(cb_args) })
      __call_attr_impl(name, {*args, cb}, kwargs)
    end

    def __call_attr_impl(name : String, args, kwargs) : PyValue
      f = LibPython.getattr(@__pyptr__, name)
      PyCall.gil do
        kwargs_ptr = nil
        unless kwargs.empty?
          kwargs_ptr = LibPy.py_dict_new
          kwargs.each do |k, v|
            pk = Conversion.from_crystal(k.to_s)
            pv = Conversion.from_crystal(v)
            LibPy.py_dict_set_item(kwargs_ptr.not_nil!, pk, pv)
            LibPy.py_decref(pk)
            LibPy.py_decref(pv)
          end
        end
        value = begin
          Conversion.to_crystal(LibPython.call_object(f, args, kwargs_ptr))
        ensure
          LibPy.py_decref(kwargs_ptr.not_nil!) if kwargs_ptr
        end
        LibPy.py_decref(f)
        value
      end
    end

    def __setattr(name : String, value)
      base = name.ends_with?('=') ? name.rchop : name
      v = Conversion.from_crystal(value)
      LibPython.setattr(@__pyptr__, base, v)
      PyCall.gil { LibPy.py_decref(v) }
      value
    end

    # --- явный вызов (аналог `obj.call` / `obj.()` в гемме) ------------------

    def call(*args, **kwargs) : PyValue
      __call_attr("__call__", *args, **kwargs)
    end

    def call(*args, **kwargs, &block : Array(PyValue) -> PyValue) : PyValue
      __call_attr("__call__", *args, **kwargs, &block)
    end

    # --- операторы → дуандеры -------------------------------------------------

    {% for op, dunder in OPERATOR_NAMES %}
      def {{op.id}}(other)
        __call_dunder({{dunder}}, other)
      end
    {% end %}

    def - : PyValue
      __getattr_or_call0("__neg__")
    end

    def ~ : PyValue
      __getattr_or_call0("__invert__")
    end

    private def __call_dunder(dunder : String, other) : PyValue
      unless LibPython.hasattr?(@__pyptr__, dunder)
        raise PyCall::Error.new("Python object #{LibPython.repr(@__pyptr__)} has no #{dunder}")
      end
      __call_attr(dunder, other)
    end

    # --- сравнения → PyObject_RichCompare --------------------------------------

    def ==(other) : Bool
      compare_other(LibPython::OP_EQ, other)
    end

    def !=(other) : Bool
      compare_other(LibPython::OP_NE, other)
    end

    def <(other) : Bool
      compare_other(LibPython::OP_LT, other)
    end

    def <=(other) : Bool
      compare_other(LibPython::OP_LE, other)
    end

    def >(other) : Bool
      compare_other(LibPython::OP_GT, other)
    end

    def >=(other) : Bool
      compare_other(LibPython::OP_GE, other)
    end

    private def compare_other(op : Int32, other) : Bool
      p = Conversion.from_crystal(other)
      begin
        LibPython.compare(op, @__pyptr__, p)
      ensure
        PyCall.gil { LibPy.py_decref(p) }
      end
    end

    # --- доступ по индексу -------------------------------------------------------

    def [](*keys) : PyValue
      key = keys.size == 1 ? keys[0] : keys
      Conversion.to_crystal(LibPython.getitem(@__pyptr__, key))
    end

    def []=(*keys, value) : Object
      key = keys.size == 1 ? keys[0] : keys
      LibPython.setitem(@__pyptr__, key, value)
      value
    end

    # --- представление / конвертация (как в гемме) --------------------------------

    def to_s(io : IO) : Nil
      io << LibPython.str(@__pyptr__)
    end

    def inspect(io : IO) : Nil
      io << LibPython.repr(@__pyptr__)
    end

    def to_i : Int64
      PyCall.gil do
        p = LibPython.check!(LibPy.py_number_long(@__pyptr__), "int()")
        v = LibPy.py_long_as_long_long(p)
        LibPy.py_decref(p)
        v
      end
    end

    def to_f : Float64
      PyCall.gil do
        p = LibPython.check!(LibPy.py_number_float(@__pyptr__), "float()")
        v = LibPy.py_float_as_double(p)
        LibPy.py_decref(p)
        v
      end
    end

    def dup : PyWrap
      PyCall.import_module("copy").__call_attr("copy", self).as(PyWrap)
    end

    def hash(hasher)
      hasher.string(LibPython.repr(@__pyptr__))
    end

    # kind_of? для python-типов (PyTypeObjectWrapper#kind_of? в гемме)
    def kind_of_python_type?(py_type : PyWrap) : Bool
      PyCall.gil do
        t = LibPython.type_of(@__pyptr__)
        target = py_type.__pyptr__
        # идём по MRO: у type-объектов __mro__ — tuple типов
        mro = LibPy.py_object_get_attr_string(target, "__mro__")
        return false if mro.null?
        LibPy.py_err_clear
        found = false
        LibPy.py_tuple_size(mro).times do |i|
          found = true if LibPy.py_tuple_get_item(mro, i) == t
        end
        LibPy.py_decref(mro)
        found
      end
    end

    # helper для traceback-строк
    def to_a_of_strings : Array(String)
      to_a.map(&.to_s)
    end

    def to_a : Array(PyValue)
      Array(PyValue).new(size) { |i| self[i] }
    end

    def size : Int64
      PyCall.len(self).as(Int64)
    end
  end
end
