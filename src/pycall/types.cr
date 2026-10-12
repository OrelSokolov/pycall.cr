# Замкнутый union для «значения из Python». Object нельзя использовать
# как generic-аргумент в Crystal, поэтому контейнеры/Proc-типы аннотируются
# этим алиасом (примитивы конвертируются, остальное — PyWrap).

module PyCall
  alias PyValue = Nil | Bool | Int64 | Float64 | String | PyWrap
end
