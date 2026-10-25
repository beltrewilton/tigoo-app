defmodule TigooServer.Fe.Generation.Schema do
  @moduledoc "Loads the schema registry and builds documents in XSD sequence order."
  alias TigooServer.Fe.Generation.{Command, Error, Xml}
  @types ~w(31 32 33 34 41 43 44 45 46 47)

  def load!(type, opts \\ []) do
    filename = cond do
      type in @types -> "e-CF #{type} v.1.0.xsd"
      type == "RFCE" -> "RFCE 32 v.1.0.xsd"
      type == "ACECF" -> "ACECF v.1.0.xsd"
      true -> Error.fail!(:schema, "Unsupported document type #{type}")
    end
    directory = Keyword.get(opts, :schema_directory, Application.app_dir(:tigoo_server, "priv/fe/xsd"))
    path = Path.join(directory, filename) |> Path.expand()
    bytes = File.read!(path)
    root = bytes |> Xml.parse!() |> Xml.children("element")
    case root do
      [declaration] ->
        tree = declaration!(declaration)
        %{path: path, sha256: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower),
          tree: tree, leaves: leaves(tree, [], [])}
      _ -> Error.fail!(:schema, "Expected one schema root in #{filename}")
    end
  end

  defp declaration!(node) do
    name = Xml.attr(node, "name") || Error.fail!(:schema, "Referenced declarations are unsupported")
    complex = Xml.child(node, "complexType")
    children = if complex do
      sequence = Xml.child(complex, "sequence") || Error.fail!(:schema, "Only inline XSD sequences are supported: #{name}")
      Enum.flat_map(Xml.elements(sequence), fn child ->
        case Xml.local(elem(child, 0)) do
          "element" -> [declaration!(child)]
          "any" -> [] # Signature contents are verified cryptographically, not by this wildcard.
          other -> Error.fail!(:schema, "Unsupported XSD compositor #{other}")
        end
      end)
    else
      []
    end
    maximum = Xml.attr(node, "maxOccurs", "1")
    %{name: name, min: String.to_integer(Xml.attr(node, "minOccurs", "1")),
      max: if(maximum == "unbounded", do: :unbounded, else: String.to_integer(maximum)),
      children: children}
  end

  defp leaves(node, parent, repeats) do
    path = parent ++ [node.name]
    repeats = if node.max == 1, do: repeats, else: repeats ++ [length(parent)]
    if node.children == [] do
      [%{name: node.name, path: path, repeats: repeats}]
    else
      Enum.flat_map(node.children, &leaves(&1, path, repeats))
    end
  end

  @doc "Builds a tree from exact schema paths, enforcing required nodes and repetition bounds."
  def build!(schema, assignments), do: build_node!(schema.tree, [], assignments) |> List.first()

  defp build_node!(node, parent, assignments) do
    instances = if node.max == 1 do
      prefix = parent ++ [{node.name, nil}]
      if Enum.any?(assignments, fn {path, _} -> List.starts_with?(path, prefix) end), do: [nil], else: []
    else
      assignments |> Map.keys() |> Enum.flat_map(fn path ->
        case Enum.at(path, length(parent)) do
          {name, index} when name == node.name and is_integer(index) ->
            if List.starts_with?(path, parent), do: [index], else: []
          _ -> []
        end
      end) |> Enum.uniq() |> Enum.sort()
    end

    if length(instances) < node.min or (node.max != :unbounded and length(instances) > node.max) do
      Error.fail!(:mapping, "XSD cardinality violated at #{Xml.path(parent ++ [{node.name, nil}])}")
    end
    if node.max != 1 and instances != [] and instances != Enum.to_list(1..length(instances)) do
      Error.fail!(:mapping, "Repeated indices must start at one and be contiguous: #{node.name}")
    end

    Enum.map(instances, fn index ->
      path = parent ++ [{node.name, index}]
      if node.children == [] do
        value = Map.fetch!(assignments, path)
        if value == "", do: Error.fail!(:mapping, "Empty field at #{Xml.path(path)}")
        Xml.leaf(node.name, value)
      else
        children = Enum.flat_map(node.children, &build_node!(&1, path, assignments))
        if children == [], do: Error.fail!(:mapping, "Empty container at #{Xml.path(path)}")
        Xml.node(node.name, children)
      end
    end)
  end

  @doc "Projects a source tree to the target schema, preserving target element order."
  def project!(schema, source) do
    assignments = Enum.reduce(schema.leaves, %{}, fn leaf, acc ->
      collect_projection(source, tl(leaf.path), [], leaf, acc)
    end)
    build!(schema, assignments)
  end

  defp collect_projection(source, [], actual, leaf, acc) do
    path = [{hd(leaf.path), nil} | actual]
    Map.put(acc, path, Xml.text(source))
  end

  defp collect_projection(source, [name | rest], actual, leaf, acc) do
    depth = length(actual) + 1
    Xml.children(source, name) |> Enum.with_index(1) |> Enum.reduce(acc, fn {node, index}, result ->
      position = if depth in leaf.repeats, do: index, else: nil
      collect_projection(node, rest, actual ++ [{name, position}], leaf, result)
    end)
  end

  def validate_file!(path, schema, opts \\ []) do
    Command.run!(Keyword.get(opts, :xmllint_path, "xmllint"), ["--nonet", "--noout", "--schema", schema.path, path])
    :ok
  end
end
