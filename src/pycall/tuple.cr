# PyCall::Tuple — обёртка python tuple (в гемме — Tuple.wrap_pyptr).

module PyCall
  class Tuple < PyWrap
    include Enumerable(PyValue)

    def each
      PyCall.gil do
        n = LibPy.py_tuple_size(__pyptr__)
        i = 0_i64
        while i < n
          yield Conversion.to_crystal_borrowed(LibPy.py_tuple_get_item(__pyptr__, i))
          i += 1
        end
      end
      self
    end

    def length : Int64
      LibPy.py_tuple_size(__pyptr__)
    end

    def size : Int64
      length
    end

    def to_a : Array(PyValue)
      Array(PyValue).new(length) { |i| self[i] }
    end
  end
end
