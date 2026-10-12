# PyCall::List — порт lib/pycall/list.rb.

module PyCall
  class List < PyWrap
    include Enumerable(PyValue)

    def each
      PyCall.gil do
        n = LibPy.py_list_size(__pyptr__)
        i = 0_i64
        while i < n
          yield Conversion.to_crystal_borrowed(LibPy.py_list_get_item(__pyptr__, i))
          i += 1
        end
      end
      self
    end

    def include?(item) : Bool
      PyCall.gil do
        p = Conversion.from_crystal(item)
        r = LibPy.py_sequence_contains(__pyptr__, p)
        LibPy.py_decref(p)
        LibPython.check_status(r, "PySequence_Contains")
        r == 1
      end
    end

    def length : Int64
      LibPy.py_list_size(__pyptr__)
    end

    def size : Int64
      length
    end

    def <<(item) : self
      append_py(item)
      self
    end

    def push(*items) : self
      items.each { |i| append_py(i) }
      self
    end

    def sort! : self
      __call_attr("sort")
      self
    end

    def sort : List
      dup.as(List).tap(&.sort!)
    end

    def to_a : Array(PyValue)
      Array(PyValue).new(length) { |i| self[i] }
    end

    private def append_py(item)
      PyCall.gil do
        p = Conversion.from_crystal(item)
        r = LibPy.py_list_append(__pyptr__, p)
        LibPy.py_decref(p)
        LibPython.check_status(r, "PyList_Append")
      end
    end
  end
end
