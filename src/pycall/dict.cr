# PyCall::Dict — порт lib/pycall/dict.rb.

module PyCall
  class Dict < PyWrap
    # NOTE: Enumerable({Object, Object}) невозможен в Crystal (Object как
    # generic-аргумент запрещён); each/to_h определены вручную, как в гемме.

    def length : Int64
      LibPy.py_dict_size(__pyptr__)
    end

    def size : Int64
      length
    end

    def has_key?(key) : Bool
      PyCall.gil do
        pk = Conversion.from_crystal(key)
        r = LibPy.py_dict_contains(__pyptr__, pk)
        LibPy.py_decref(pk)
        LibPython.check_status(r, "PyDict_Contains")
        r == 1
      end
    end

    def include?(key) : Bool
      has_key?(key)
    end

    def key?(key) : Bool
      has_key?(key)
    end

    # как в гемме: отсутствующий ключ → nil вместо KeyError
    def [](key) : PyValue
      super
    rescue PyError
      nil
    end

    def delete(key) : PyValue
      v = self[key]
      LibPython.delitem(__pyptr__, key)
      v
    end

    def each
      PyCall.gil do
        pos = 0_i64
        k = uninitialized LibPy::PyObjectT*
        v = uninitialized LibPy::PyObjectT*
        while LibPy.py_dict_next(__pyptr__, pointerof(pos), pointerof(k), pointerof(v)) == 1
          yield({Conversion.to_crystal_borrowed(k), Conversion.to_crystal_borrowed(v)})
        end
      end
      self
    end

    def to_h : Hash(PyValue, PyValue)
      hash = {} of PyValue => PyValue
      each { |(k, v)| hash[k] = v }
      hash
    end
  end
end
