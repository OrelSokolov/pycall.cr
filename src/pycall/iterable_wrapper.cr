# PyCall::IterableWrapper — порт lib/pycall/iterable_wrapper.rb:
# GetIter + PyIter_Next, StopIteration завершает each.

module PyCall
  class IterableWrapper
    include Enumerable(PyValue)

    def initialize(@obj : PyWrap)
      unless PyCall.hasattr?(@obj, "__iter__")
        raise ArgumentError.new("#{LibPython.repr(@obj.__pyptr__)} object is not iterable")
      end
    end

    def each
      PyCall.gil do
        iter = LibPython.check!(LibPy.py_object_get_iter(@obj.__pyptr__), "PyObject_GetIter")
        begin
          loop do
            item = LibPy.py_iter_next(iter)
            if item.null?
              if !LibPy.py_err_occurred.null?
                if LibPy.py_err_exception_matches(LibPy.py_exc_stop_iteration) != 0
                  LibPy.py_err_clear
                  break
                end
                PyError.fetch_and_raise("PyIter_Next")
              end
              break
            end
            yield Conversion.to_crystal(item) # steals
          end
        ensure
          LibPy.py_decref(iter)
        end
      end
      self
    end
  end
end
