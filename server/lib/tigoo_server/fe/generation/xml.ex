defmodule TigooServer.Fe.Generation.Xml do
  @moduledoc false
  alias TigooServer.Fe.Generation.Error
  @ds "http://www.w3.org/2000/09/xmldsig#"

  def parse!(<<239, 187, 191, bytes::binary>>), do: parse!(bytes)
  def parse!(bytes) when is_binary(bytes) do
    if not String.valid?(bytes) or String.contains?(bytes, ["<!DOCTYPE", "<!ENTITY", "\0"]) or
         Regex.match?(~r/<\?(?!xml\s)/, bytes) do
      Error.fail!(:xml, "Unsupported XML content")
    end

    case Saxy.SimpleForm.parse_string(bytes, expand_entity: {TigooServer.Sign, :reject_entity, []}) do
      {:ok, root} -> root
      {:error, _} -> Error.fail!(:xml, "Malformed XML")
    end
  end

  def local(name), do: name |> String.split(":") |> List.last()
  def elements({_, _, children}), do: Enum.filter(children, &is_tuple/1)
  def children(node, name), do: Enum.filter(elements(node), &(local(elem(&1, 0)) == name))
  def child(node, name), do: List.first(children(node, name))
  def attr({_, attrs, _}, name, default \\ nil) do
    case List.keyfind(attrs, name, 0) do
      {_, value} -> value
      nil -> default
    end
  end

  def text(nil), do: nil
  def text({_, _, children}), do: Enum.map_join(children, fn
    value when is_binary(value) -> value
    node when is_tuple(node) -> text(node)
  end)

  def value(node, path) do
    Enum.reduce_while(path, node, fn name, current ->
      case child(current, name) do
        nil -> {:halt, nil}
        next -> {:cont, next}
      end
    end) |> text()
  end

  def node(name, children), do: {name, [], children}
  def leaf(name, value), do: node(name, [value])

  def encode(node) do
    node |> escape() |> Saxy.encode!(version: "1.0", encoding: "UTF-8")
  end

  defp escape({name, attrs, children}) do
    Saxy.XML.element(name, attrs, Enum.map(children, fn
      text when is_binary(text) -> Saxy.XML.characters(text)
      child -> escape(child)
    end))
  end

  def at(node, []), do: node
  def at(node, [{name, index} | rest]) do
    case Enum.at(children(node, name), (index || 1) - 1) do
      nil -> nil
      next -> at(next, rest)
    end
  end

  def path(path) do
    "/" <> Enum.map_join(path, "/", fn
      {name, nil} -> name
      {name, index} -> "#{name}[#{index}]"
    end)
  end

  @doc "Reads the namespace-resolved final XMLDSig and its signing-certificate fingerprint."
  def signature!(root) do
    expanded = expand(root, %{})
    signatures = Enum.filter(elements(expanded), &(elem(&1, 0) == {@ds, "Signature"}))

    case signatures do
      [signature] ->
        if List.last(elements(expanded)) != signature, do: Error.fail!(:signature, "Signature must be last")
        value = signature |> expanded_value([{@ds, "SignatureValue"}]) |> compact()
        certificate = signature |> expanded_value([{@ds, "KeyInfo"}, {@ds, "X509Data"}, {@ds, "X509Certificate"}]) |> compact()

        with {:ok, decoded} when byte_size(decoded) > 0 <- Base.decode64(value),
             {:ok, der} when byte_size(der) > 0 <- Base.decode64(certificate) do
          %{value: value, certificate_sha256: :crypto.hash(:sha256, der) |> Base.encode16(case: :lower)}
        else
          _ -> Error.fail!(:signature, "Invalid signature or certificate encoding")
        end

      _ -> Error.fail!(:signature, "Expected exactly one XMLDSig Signature")
    end
  end

  defp compact(nil), do: ""
  defp compact(text), do: String.replace(text, ~r/\s+/, "")
  defp expanded_value(node, []), do: text(node)
  defp expanded_value(node, [name | rest]) do
    case Enum.filter(elements(node), &(elem(&1, 0) == name)) do
      [next] -> expanded_value(next, rest)
      _ -> nil
    end
  end

  defp expand({name, attrs, children}, inherited) do
    namespaces = Enum.reduce(attrs, inherited, fn
      {"xmlns", uri}, acc -> Map.put(acc, "", uri)
      {"xmlns:" <> prefix, uri}, acc -> Map.put(acc, prefix, uri)
      _, acc -> acc
    end)

    expanded = case String.split(name, ":", parts: 2) do
      [local] -> {Map.get(namespaces, "", ""), local}
      [prefix, local] -> {Map.get(namespaces, prefix), local}
    end

    {expanded, attrs, Enum.map(children, fn
      text when is_binary(text) -> text
      child -> expand(child, namespaces)
    end)}
  end
end
