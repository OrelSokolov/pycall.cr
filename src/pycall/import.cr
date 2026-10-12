# PyCall::Import — порт lib/pycall/import.rb: pyimport / pyfrom.

module PyCall
  module Import
    macro pyimport(name, as alt = nil)
      {% n = name.id.stringify %}
      {% if n.includes?('.') && alt.nil? %}
        {% raise "pyimport #{n}: dotted module needs `as: \u{2E}\u{2E}\u{2E}` alias" %}
      {% end %}
      def {{ (alt || name).id }} : ::PyCall::PyWrap
        PyCall.import_module({{n}})
      end
    end

    # pyfrom :math, import: [:pi, :sqrt]
    # pyfrom :collections, import: {ordered_dict: :OrderedDict}
    macro pyfrom(name, import imports)
      {% n = name.id.stringify %}
      {% if imports.is_a?(SymbolLiteral) %}
        {% imports = [imports] %}
      {% end %}
      {% if imports.is_a?(ArrayLiteral) %}
        {% for imp in imports %}
          {% iname = imp.id.stringify %}
          def {{iname.id}} : Object
            PyCall.import_module({{n}}).__getattr_or_call0({{iname}})
          end
        {% end %}
      {% elsif imports.is_a?(NamedTupleLiteral) %}
        {% for alias_name, imp in imports %}
          {% iname = imp.id.stringify %}
          def {{alias_name.id}} : Object
            PyCall.import_module({{n}}).__getattr_or_call0({{iname}})
          end
        {% end %}
      {% else %}
        {% raise "pyfrom: import must be a Symbol, Array of Symbols or alias NamedTuple" %}
      {% end %}
    end
  end
end
