# PyCall::Set — порт lib/pycall/set.rb.

module PyCall
  class Set < PyWrap
    def size : Int64
      LibPy.py_set_size(__pyptr__)
    end

    def length : Int64
      size
    end

    def include?(obj) : Bool
      PyCall.gil do
        p = Conversion.from_crystal(obj)
        r = LibPy.py_set_contains(__pyptr__, p)
        LibPy.py_decref(p)
        LibPython.check_status(r, "PySet_Contains")
        r == 1
      end
    end
  end
end
