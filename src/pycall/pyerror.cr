# PyCall::Error / PyCall::PyError — порт lib/pycall/error.rb и pyerror.rb.

module PyCall
  class Error < ::Exception
  end

  class PyError < Error
    getter type : PyWrap
    getter value : PyWrap | Nil | Bool | Int64 | Float64 | String
    getter traceback : PyWrap | Nil

    def initialize(@type, @value, @traceback)
      super("Exception occurred in Python")
    end

    # PyErr_Fetch + NormalizeException, как pycall_pyerror_fetch_and_raise.
    def self.fetch_and_raise(context : String) : NoReturn
      t = uninitialized LibPy::PyObjectT*
      v = uninitialized LibPy::PyObjectT*
      tb = uninitialized LibPy::PyObjectT*
      LibPy.py_err_fetch(pointerof(t), pointerof(v), pointerof(tb))
      LibPy.py_err_normalize_exception(pointerof(t), pointerof(v), pointerof(tb))
      if t.null?
        LibPy.py_err_clear
        LibPy.py_decref(v) unless v.null?
        LibPy.py_decref(tb) unless tb.null?
        raise Error.new(context)
      end
      type = PyWrap.wrap(t)                                   # steals
      value = v.null? ? nil : Conversion.to_crystal(v)        # steals
      traceback = tb.null? ? nil : PyWrap.wrap(tb)            # steals
      raise new(type, value, traceback)
    end

    def message : String
      msg = "#{@type}: #{@value}"
      begin
        tb = format_traceback
        unless tb.empty?
          msg += "\n" + tb.join
        end
      rescue
        # форматирование трейсбека не должно маскировать исходную ошибку
      end
      msg
    end

    private def format_traceback : Array(String)
      return [] of String unless tb = @traceback
      formatted = PyCall.import_module("traceback").__call_attr("format_tb", tb)
      return [] of String unless formatted.is_a?(PyWrap)
      formatted.to_a_of_strings
    end
  end
end
