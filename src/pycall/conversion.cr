# Конвертация типов Crystal ↔ Python — порт Conversion.from_ruby/to_ruby
# из ext/pycall/pycall.c.

module PyCall
  module Conversion
    class UnconvertibleError < PyCall::Error
    end

    # Crystal → Python. Возвращает НОВУЮ ссылку (или incref-нутую).
    def self.from_crystal(value) : LibPy::PyObjectT*
      PyCall.gil do
        case value
        when PyWrap
          LibPy.py_incref(value.__pyptr__)
          value.__pyptr__
        when Nil
          LibPy.py_incref(LibPython.none)
          LibPython.none
        when Bool
          LibPy.py_bool_from_long(value ? 1 : 0)
        when Int
          LibPy.py_long_from_long_long(value.to_i64)
        when Float
          LibPy.py_float_from_double(value.to_f64)
        when String
          LibPython.check!(LibPy.py_unicode_from_string(value.to_unsafe), "PyUnicode_FromString")
        when Symbol
          LibPython.check!(LibPy.py_unicode_from_string(value.to_s.to_unsafe), "PyUnicode_FromString")
        when Array
          list = LibPy.py_list_new(value.size)
          raise Error.new("PyList_New failed") if list.null?
          value.each_with_index do |el, i|
            LibPy.py_list_set_item(list, i, from_crystal(el)) # steals
          end
          list
        when Hash
          dict = LibPy.py_dict_new
          raise Error.new("PyDict_New failed") if dict.null?
          value.each do |k, v|
            pk = from_crystal(k)
            pv = from_crystal(v)
            LibPy.py_dict_set_item(dict, pk, pv) # increfs внутри
            LibPy.py_decref(pk)
            LibPy.py_decref(pv)
          end
          dict
        when Range
          from_range(value)
        when Proc(Array(PyValue), PyValue)
          cb = Callable.new(value)
          p = cb.__pyptr__
          LibPy.py_incref(p)
          p
        else
          raise UnconvertibleError.new("Unable to convert #{value.class} to Python object")
        end
      end
    end

    # Range → slice: 1..3 → [1:4], 1...3 → [1:3], beginless/endless → None-границы.
    # Поддерживаются целочисленные диапазоны (использование срезов списков).
    private def self.from_range(r : Range) : LibPy::PyObjectT*
      b = r.begin
      e = r.end
      if !b.nil? && !b.is_a?(Int)
        raise UnconvertibleError.new("Unable to convert #{r} (#{r.class}) to Python slice: non-integer begin")
      end
      if !e.nil? && !e.is_a?(Int)
        raise UnconvertibleError.new("Unable to convert #{r} (#{r.class}) to Python slice: non-integer end")
      end
      start = b.nil? ? none_incref : from_crystal(b.as(Int))
      stop =
        if e.nil?
          none_incref
        else
          from_crystal(r.exclusive? ? e : e.as(Int).succ)
        end
      slice = LibPy.py_slice_new(start, stop, none_incref)
      LibPy.py_decref(start)
      LibPy.py_decref(stop)
      LibPython.check!(slice, "PySlice_New")
    end

    private def self.none_incref : LibPy::PyObjectT*
      LibPy.py_incref(LibPython.none)
      LibPython.none
    end

    # Python → Crystal. ЗАБИРАЕТ переданную ссылку (steals).
    # Примитивы конвертируются, остальное оборачивается в PyWrap
    # (List/Dict/Tuple/Set — как register_python_type_mapping в гемме).
    def self.to_crystal(p : LibPy::PyObjectT*) : PyValue
      PyCall.gil do
        return nil if p == LibPython.none
        case LibPython.type_of(p)
        when .==(LibPython.py_bool_type)
          v = LibPy.py_object_is_true(p)
          LibPy.py_decref(p)
          v == 1
        when .==(LibPython.py_long_type)
          v = LibPy.py_long_as_long_long(p)
          if v == -1 && !LibPy.py_err_occurred.null?
            # переполнение Int64 — оставляем обёрткой
            LibPy.py_err_clear
            PyWrap.wrap(p)
          else
            LibPy.py_decref(p)
            v
          end
        when .==(LibPython.py_float_type)
          v = LibPy.py_float_as_double(p)
          LibPy.py_decref(p)
          v
        when .==(LibPython.py_unicode_type)
          s = String.new(LibPy.py_unicode_as_utf8(p))
          LibPy.py_decref(p)
          s
        else
          PyWrap.wrap(p)
        end
      end
    end

    # Как to_crystal, но для заимствованной (borrowed) ссылки.
    def self.to_crystal_borrowed(p : LibPy::PyObjectT*) : PyValue
      PyCall.gil { LibPy.py_incref(p) }
      to_crystal(p)
    end
  end
end
