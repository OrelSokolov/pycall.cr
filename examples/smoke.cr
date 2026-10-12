# Пример использования pycall_cr 1-в-1 с API гема pycall.
# Запуск: crystal run examples/smoke.cr
require "../src/pycall_cr"

math = PyCall.import_module("math")
p math.pi
p math.sin(0.5)
p PyCall.python_version

# eval/exec
PyCall.exec("y = 40 + 2")
p PyCall.eval("y")

# list / dict / tuple / set
lst = PyCall.eval("[3, 1, 2]").as(PyCall::List)
p lst.to_a
lst.sort!
p lst.to_a
lst << 99
p lst.to_a
p lst.include?(2)

d = PyCall.eval("{'a': 1, 'b': 2}").as(PyCall::Dict)
p d["a"]
p d["zzz"]          # nil
p d.has_key?("b")
p d.to_h
p d.length

t = PyCall.eval("(1, 2, 3)").as(PyCall::Tuple)
p t.to_a

s = PyCall.eval("{1, 2}").as(PyCall::Set)
p s.size
p s.include?(1)

# operators on wrapped objects (Fraction — не примитив, остаётся обёрткой)
fractions = PyCall.import_module("fractions")
a = fractions.Fraction(1, 3).as(PyCall::PyWrap)
b = fractions.Fraction(1, 6).as(PyCall::PyWrap)
p a + b
p a * b
p a - b
p a / b

# comparison
p a > b
p a == fractions.Fraction(1, 3)

# str/repr/to_i/to_f
p PyCall.eval("'abc' * 3")
p PyCall.eval("'42'").as(String).to_i
p PyCall.eval("'2.5'").as(String).to_f
p PyCall.eval("[1, 'x']").inspect

# setattr/getattr on module
m = PyCall.import_module("math")
PyCall.setattr(m, "myflag", 123)
p PyCall.getattr(m, "myflag")
p PyCall.hasattr?(m, "sin")

# callable? / len / dir / tuple
p PyCall.callable?(PyCall.eval("abs").as(PyCall::PyWrap))
p PyCall.callable?(PyCall.eval("42"))
p PyCall.len(lst)
p PyCall.dir(math).as(PyCall::List).to_a.size > 10

# kwargs: round(2.5678, ndigits=2)
p PyCall.builtins.round(2.5678, ndigits: 2)

# callback: sorted with key
sorted = PyCall.builtins.sorted(PyCall.eval("[-2, 3, -5, 1]"),
  key: PyCall::Callable.new { |args| args[0].as(Int64).abs })
p sorted

# with (context manager)
CTX_CODE = "class Ctx:\n" + \
  "    def __enter__(self):\n" + \
  "        return 'entered'\n" + \
  "    def __exit__(self, t, v, tb):\n" + \
  "        self.exited = True\n" + \
  "        return True"
PyCall.exec(CTX_CODE)
ctx = PyCall.eval("Ctx()").as(PyCall::PyWrap)
PyCall.with(ctx) { |x| p x }

# error handling
begin
  PyCall.eval("1/0")
rescue e : PyCall::PyError
  puts "PyError: #{e.type}"
end

# iterable
p PyCall.iterable(PyCall.eval("[10, 20]").as(PyCall::PyWrap)).to_a

# Range → slice
p PyCall.eval("[0,1,2,3,4,5,6]").as(PyCall::PyWrap)[2..4]

# pyimport/pyfrom
class App
  include PyCall::Import
  pyimport :math
  pyfrom :math, import: [:pi]
end
p App.new.math.sin(1)
p App.new.pi
puts "SMOKE OK"
