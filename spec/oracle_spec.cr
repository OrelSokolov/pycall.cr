# Oracle spec: порт обязан воспроизвести oracle/expected.yml — значения
# сняты с настоящего Python 3.13.7 (python3) в том же окружении.
# Проверяется вся поверхность API 1-в-1 с геммою pycall.

require "spec"
require "../src/pycall_cr"

EXPECTED = begin
  hash = {} of String => String
  File.read("#{__DIR__}/../oracle/expected.yml").each_line do |line|
    if line.includes?('\t')
      id, value = line.split('\t', 2)
      hash[id] = value.chomp
    end
  end
  hash
end

def check(id, value)
  (EXPECTED[id]? || "MISSING #{id}").should eq value.to_s
end

CTX_CODE = "class Ctx:\n" + \
  "    def __enter__(self):\n" + \
  "        return 'entered'\n" + \
  "    def __exit__(self, t, v, tb):\n" + \
  "        return True\n"

class ImportApp
  include PyCall::Import
  pyimport :math
  pyfrom :math, import: [:pi]
end

describe "PyCall oracle" do
  math = PyCall.import_module("math")

  it "version" do
    check("python.version", PyCall.python_version)
  end

  it "module attrs and calls (method_missing)" do
    check("math.pi", math.pi)
    check("math.sin(0.5)", math.sin(0.5))
    check("math.floor(3.7)", math.floor(3.7))
    check("math.hypot(3,4)", math.hypot(3, 4))
  end

  it "eval / exec через __main__.__dict__" do
    PyCall.exec("y = 40 + 2")
    check("eval.int", PyCall.eval("y"))
  end

  it "List wrapper" do
    lst = PyCall.eval("[3, 1, 2]").as(PyCall::List)
    check("list.to_a", lst.to_a)
    lst.sort!
    check("list.sort!", lst.to_a)
    lst << 99
    check("list.push", lst.to_a)
    check("list.include?", lst.include?(2))
    check("list.len", PyCall.len(lst))
  end

  it "Dict wrapper" do
    d = PyCall.eval("{'a': 1, 'b': 2}").as(PyCall::Dict)
    check("dict.get", d["a"])
    check("dict.missing", d["zzz"].to_s)
    check("dict.has_key?", d.has_key?("b"))
    check("dict.length", d.length)
    check("dict.to_h", d.to_h.map { |k, v| "#{k}=#{v}" }.sort.join(";"))
    check("dict.delete", d.delete("b"))
  end

  it "Tuple wrapper" do
    t = PyCall.eval("(1, 2, 3)").as(PyCall::Tuple)
    check("tuple.to_a", t.to_a)
    check("pycall.tuple", PyCall.tuple([4, 5]).to_a)
  end

  it "Set wrapper" do
    s = PyCall.eval("{1, 2}").as(PyCall::Set)
    check("set.size", s.size)
    check("set.include?", s.include?(1))
  end

  it "python operators через дуандеры (Fraction)" do
    fractions = PyCall.import_module("fractions")
    a = fractions.Fraction(1, 3).as(PyCall::PyWrap)
    b = fractions.Fraction(1, 6).as(PyCall::PyWrap)
    check("fraction.add", a + b)
    check("fraction.mul", a * b)
    check("fraction.sub", a - b)
    check("fraction.div", a / b)
    check("fraction.gt", a > b)
    check("fraction.eq", a == fractions.Fraction(1, 3))
  end

  it "строки / repr / to_i / to_f" do
    check("str.mul", PyCall.eval("'abc' * 3"))
    check("str.to_i", PyCall.eval("'42'").as(String).to_i)
    check("str.to_f", PyCall.eval("'2.5'").as(String).to_f)
    check("repr", PyCall.eval("[1, 'x']").as(PyCall::PyWrap).inspect)
  end

  it "getattr / setattr / hasattr?" do
    m = PyCall.import_module("math")
    PyCall.setattr(m, "myflag", 123)
    check("setattr", PyCall.getattr(m, "myflag"))
    check("hasattr?", PyCall.hasattr?(m, "sin"))
  end

  it "callable? / same?" do
    check("callable?.func", PyCall.callable?(PyCall.eval("abs")))
    check("callable?.int", PyCall.callable?(PyCall.eval("42")))
    check("same?", PyCall.same?(math, PyCall.import_module("math")))
  end

  it "kwargs-вызов" do
    check("kwargs.round", PyCall.builtins.round(2.5678, ndigits: 2))
  end

  it "Proc → python callable (sorted с key=)" do
    key = PyCall::Callable.new { |args| args[0].as(Int64).abs }
    sorted = PyCall.builtins.sorted(PyCall.eval("[-2, 3, -5, 1]").as(PyCall::PyWrap), key: key)
    check("callback.sorted", sorted.as(PyCall::List).to_a)
  end

  it "with (контекстный менеджер)" do
    PyCall.exec(CTX_CODE)
    ctx = PyCall.eval("Ctx()").as(PyCall::PyWrap)
    entered = nil
    PyCall.with(ctx) { |v| entered = v }
    check("with.enter", entered)
  end

  it "PyError с python-типом" do
    begin
      PyCall.eval("1/0")
      fail("должно было упасть PyError")
    rescue e : PyCall::PyError
      check("error.type", e.type)
    end
  end

  it "iterable" do
    check("iterable", PyCall.iterable(PyCall.eval("[10, 20]").as(PyCall::PyWrap)).to_a)
  end

  it "Range → slice" do
    check("range.slice", PyCall.eval("[0,1,2,3,4,5,6]").as(PyCall::PyWrap)[2..4].as(PyCall::List).to_a)
  end

  it "конвертация Array/Hash из Crystal" do
    check("conv.array", PyCall.eval("list").as(PyCall::PyWrap).call([1, 2, 3]).as(PyCall::List).to_a)
    d = PyCall.eval("dict").as(PyCall::PyWrap).call({"a" => 1, "b" => 2}).as(PyCall::Dict)
    check("conv.hash", d.to_h.map { |k, v| "#{k}=#{v}" }.sort.join(";"))
  end

  it "pyimport / pyfrom" do
    app = ImportApp.new
    check("pyimport.sin", app.math.sin(1))
    check("pyfrom.pi", app.pi)
  end

  # Глобальный MUTEX: параллельные вызовы из множества фибер (на N тредах)
  # не роняют интерпретатор и не теряют данные.
  it "параллельные вызовы: 8 фибер × 100 итераций" do
    shared = PyCall.eval("[]").as(PyCall::List)
    ch = Channel(Nil).new
    8.times do
      spawn do
        100.times do |i|
          PyCall.eval("#{i} * 2").as(Int64).should eq(i * 2)
          math.sin(0.5)
          shared << i
          shared.size
        end
        ch.send(nil)
      end
    end
    8.times { ch.receive }
    shared.size.should eq(800)
  end

  it "параллельные вызовы с колбэками" do
    ch = Channel(Nil).new
    4.times do
      spawn do
        20.times do |i|
          key = PyCall::Callable.new { |args| args[0].as(Int64).abs }
          sorted = PyCall.builtins.sorted(PyCall.eval("[-#{i}, #{i + 1}]").as(PyCall::PyWrap), key: key)
          sorted.as(PyCall::List).to_a.size.should eq(2)
        end
        ch.send(nil)
      end
    end
    4.times { ch.receive }
  end
end
