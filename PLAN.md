# pycall.cr — порт гема pycall (mrkn/pycall)

Порт [pycall](https://github.com/mrkn/pycall) на Crystal: вызов Python
из Crystal поверх **CPython C API** (libpython). Оригинал скачан и
разобран (`/tmp/pycall-src`, gem 1.6.x, Python 3.13).

## Технология

Оригинал: `dlopen` libpython + C-биндинги (`ext/pycall`), обёртки
`PyObject*` с refcounting, GIL-менеджмент, `method_missing`-диспетчеризация,
конвертация типов, `PyError` с traceback.

Порт биндит **ту же libpython** напрямую (`@[Link("python3.13")]`,
компиляция-time линковка вместо рантайм-`dlopen` гема).

## Соответствие фич (1-в-1 с гема)

| Гем (lib/pycall.rb, pyobject_wrapper.rb, C-ext)          | Порт                                          |
|-----------------------------------------------------------|-----------------------------------------------|
| `PyCall.init` / `PYTHON_VERSION` / `PYTHON_DESCRIPTION`   | `PyCall.init!`, `PyCall.python_version` …     |
| `PyCall.import_module` → PyModuleWrapper                  | `PyCall.import_module` → `PyWrap`             |
| `PyCall.builtins` / `PyCall.sys`                          | то же (ленивые, авто-init)                    |
| `PyCall.eval` / `PyCall.exec` (через builtins, `__main__.__dict__`) | то же                          |
| `PyCall.getattr/hasattr?/setattr/delattr`                 | то же                                         |
| `PyCall.len/dir/callable?/same?/tuple/iterable/with`      | то же                                         |
| `method_missing`: getter / `name=` / вызов с аргументами  | `macro method_missing` + `__getattr_or_call0` |
| семантика атрибута (C-ext pcall.c:1209): не-callable → значение; callable (не тип) → вызвать с 0..N аргументов | та же |
| операторы `+ - * / % ** << >> & | ^ ~ -@` → `__add__`…    | то же                                         |
| сравнения `== != < <= > >=` → `PyObject_RichCompare`      | то же                                         |
| `[] / []=` → GetItem/SetItem (Range → slice)              | то же                                         |
| `call(*args)` (+kwargs)                                   | то же                                         |
| `inspect/to_s/to_i/to_f/dup`                              | то же                                         |
| `List`: each/Enumerable, include?, length, `<<`/push, sort/sort!, to_a | `PyCall::List`                     |
| `Dict`: has_key?, `[]`(nil при отсутствии), delete, each, to_h, length | `PyCall::Dict`                     |
| `Tuple` / `Set`                                           | `PyCall::Tuple` / `PyCall::Set`               |
| `IterableWrapper` (GetIter/PyIter_Next, StopIteration)    | `PyCall::IterableWrapper`                     |
| `PyError` (type/value/traceback, format_tb)               | `PyCall::PyError`                             |
| Ruby Proc/блок → python callable (libffi в гемме)         | `PyCall::Callable` (PyCFunction + PyCapsule)  |
| `include PyCall::Import`; `pyimport`/`pyfrom`             | то же                                         |
| GIL: `PyGILState_Ensure/Release` вокруг вызовов           | `PyCall.gil { }` (обязателен: фиберы на N тредах) |
| `Conversion.from_ruby/to_ruby` (nil/bool/int/float/str/array/hash/range→slice/proc) | `Conversion.from_crystal/to_crystal` |
| `register_python_type_mapping` (list→List и т.д.)         | диспетч по `ob_type` в `PyWrap.wrap`          |

## Осознанные отклонения

- **Линковка** — компиляция-time (`-lpython3.13`), не рантайм-поиск
  libpython как в гемме (dlopen). Причина: в Crystal нет дешёвого
  рантайм-резолва `fun`-символов; фича-сет не меняется.
- **`method_missing`** в Crystal — compile-time макрос: имена методов
  известны на компиляции (как у 99% использования pycall), но нет
  runtime-`send`. Семантика вызова — 1-в-1 с C-ext гема (pycall.c:1209):
  голый атрибут не-callable → значение; callable (не тип) → вызвать;
  `x = v` → setattr.
- **`PyValue` вместо Object**: в Crystal `Object` нельзя использовать как
  generic-аргумент, поэтому конвертированные значения — замкнутый union
  `Nil | Bool | Int64 | Float64 | String | PyWrap`. Для python-операторов
  на результатах вызовов нужен явный `.as(PyCall::PyWrap)`.
- **Блоки**: вместо нетипизированного блока Ruby — типизированный
  `&block : Array(PyValue) -> PyValue` (обёртка `PyCall::Callable`,
  PyCFunction + PyCapsule-registry вместо libffi). Через
  `method_missing` блок не пробрасывается (запрет `yield` в захваченном
  блоке) — блок передаётся явно в `#call` / как `Callable` в kwargs
  (пример: `sorted(list, key: Callable.new { ... })`).
- `coerce`/`SwappedOperationAdapter` (py-объект справа от примитива) —
  непортируемо в Crystal (нет coerce-протокола). Явный `.call`.
- `PyCall::List = builtins.list` (константа = python-тип) — в Crystal
  имя занято классом-обёрткой; python-тип доступен через
  `PyCall.eval("list")`.

## Инженерные находки (важно для сопровождения)

- **Типизированный `&block` в Crystal обязателен**: вызов метода без
  блока уходит в `method_missing`. Комбинация с нашим `method_missing`
  (который генерирует вызовы `__call_attr`...) давала бесконечную
  рекурсию расширений макроса → **10 GiB RAM и сегфолт компилятора**.
  Лечение: перегрузки с/без блока (pyobject_wrapper.cr).
- **Tuple ≠ Array в аннотациях**: `*args`-сплит не совпадает с
  параметром `args : Array` и тоже уходит в `method_missing` → та же
  рекурсия. Параметры impl нетипизированы.
- `call.named_args` в макросе — `Nop` при отсутствии (у него нет
  `empty?`); проверять через `!call.named_args`.
- Символы CPython: `_Py_NoneStruct` / `_Py_TrueStruct` / `_Py_FalseStruct`
  (с подчёркиванием, это структуры, берём `pointerof`), типы —
  `PyList_Type` и т.п., исключения — `PyExc_*` (указатели).
- **GIL-дисциплина**: после `Py_Initialize` GIL отдаётся
  (`PyEval_SaveThread`); каждый вызов CPython — под
  `PyGILState_Ensure/Release` (`PyCall.gil`), включая ВСЕ
  `Py_IncRef/Py_DecRef` (в т.ч. в финалайзерах — фиберы живут на N
  тредах, decref без GIL роняет интерпретатор).
- **Глобальный MUTEX** (`PyCall::MUTEX`): сериализует ВЕСЬ доступ к
  Python из Crystal — составные операции (getattr→call→convert)
  атомарны, interleaving фибер на разных тредах исключён. Вложенные
  `PyCall.gil` на том же треде идут по быстрому пути (`PyGILState_Check`),
  не беря мьютекс повторно (иначе дедлок на нереентерабельном Mutex);
  трамплин колбэка из Python держит GIL без мьютекса и тоже идёт по
  быстрому пути — порядок проверок критичен против дедлока.
- **Инвариант инициализации**: `Py_Initialize` обязан произойти до
  любого `PyGILState_*`. `ensure_init!` встроен в `PyCall.gil` —
  единая точка входа (раньше `PyCall.eval → main_dict` мог взять GIL
  на неинициализированном интерпретаторе → сегфолт внутри CPython;
  спеки этого не ловили, т.к. первым вызовом всегда был import_module).
- **Тесты на параллелизм**: 8 фибер × 100 итераций (eval + общий
  python-list) и 4 фиберы с колбэками — в `spec/oracle_spec.cr`.

## Статус

**Готово, зелёное**: `crystal spec` — 19 examples / 0 failures,
сверка с `oracle/expected.yml` (значения сняты с настоящего Python
3.13.7). `examples/smoke.cr` — сквозной пример всего API.

## Запуск

```sh
cd pycall.cr && crystal spec              # нужен python3.13 + libpython3.13.so
crystal run examples/smoke.cr
```
