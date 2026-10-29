defmodule TigooServer.FeXml do
  @moduledoc false

  import Saxy.XML, only: [element: 3, characters: 1]
  require Logger

  alias TigooServer.Fe.Generation.{Command, Error}

  @types ~w(31 32 33 34 41 43 44 45 46 47)
  @ds "http://www.w3.org/2000/09/xmldsig#"

  def parse(xml) when is_binary(xml) and byte_size(xml) <= 5_000_000 do
    with true <- String.valid?(xml) and not String.contains?(xml, ["\0", "<!DOCTYPE", "<!ENTITY"]),
         false <- Regex.match?(~r/<\?(?!xml\s)/, xml),
         {:ok, {"ECF", _, _} = document} <- Saxy.SimpleForm.parse_string(xml,
           expand_entity: {TigooServer.Sign, :reject_entity, []}),
         issuer when is_binary(issuer) <- value(document, ~w(Encabezado Emisor RNCEmisor)),
         buyer when is_binary(buyer) <- value(document, ~w(Encabezado Comprador RNCComprador)),
         encf when is_binary(encf) <- value(document, ~w(Encabezado IdDoc eNCF)),
         true <- Regex.match?(~r/\A(?:[0-9]{9}|[0-9]{11})\z/, issuer),
         true <- Regex.match?(~r/\A(?:[0-9]{9}|[0-9]{11})\z/, buyer),
         true <- Regex.match?(~r/\AE[0-9]{12}\z/, encf) do
      {:ok, document, %{issuer_rnc: issuer, buyer_rnc: buyer, encf: encf,
        type: value(document, ~w(Encabezado IdDoc TipoeCF))}}
    else
      _ -> {:error, :invalid_xml}
    end
  rescue
    _ -> {:error, :invalid_xml}
  end

  def parse(_), do: {:error, :invalid_xml}

  def validate(document, type) when type in @types do
    encf = value(document, ~w(Encabezado IdDoc eNCF))

    if is_binary(encf) and String.slice(encf, 1, 2) == type do
      validate_schema(document, "e-CF #{type} v.1.0.xsd")
    else
      {:error, :invalid_schema}
    end
  end

  def validate(_, _), do: {:error, :invalid_schema}

  def validate_receipt(xml) do
    with {:ok, document} <- Saxy.SimpleForm.parse_string(xml) do
      validate_schema(document, "ARECF v1.0.xsd")
    end
  end

  defp value({_name, _attrs, children}, [name | rest]) do
    case Enum.filter(children, &match?({^name, _, _}, &1)) do
      [child] -> value(child, rest)
      _ -> nil
    end
  end

  defp value({_name, _attrs, [text]}, []) when is_binary(text), do: text
  defp value(_, _), do: nil

  defp validate_schema(document, filename) do
    schema = Application.app_dir(:tigoo_server, "priv/fe/xsd/" <> filename)
    # Preserve the existing strict element/attribute checks and signature
    # placeholder. Verify the digital signature separately on original bytes.
    names = Regex.scan(~r/\bname\s*=\s*["']([^"']+)["']/, File.read!(schema), capture: :all_but_first)
      |> List.flatten() |> MapSet.new()
    projection = project_root(document, names) |> Saxy.encode!()
    validate_projection(projection, schema)
    :ok
  rescue
    exception in Error ->
      # xmllint exit 3 means the document violates its XSD. Dependency errors,
      # schema loading failures and timeouts are service failures, not evidence
      # that an otherwise valid incoming invoice should be rejected.
      if exception.stage == :validation and String.contains?(exception.message, "Native command exited 3:") do
        Logger.error("FE XSD failed schema=#{filename} validator=xmllint reason=invalid_schema")
        {:error, :invalid_schema}
      else
        Logger.error("FE XSD failed schema=#{filename} validator=xmllint reason=verifier_unavailable stage=#{exception.stage}")
        {:error, :verifier_unavailable}
      end
    exception in File.Error ->
      Logger.error("FE XSD failed schema=#{filename} reason=validation_file_unavailable action=#{exception.action}")
      {:error, :verifier_unavailable}
    exception ->
      Logger.error("FE XSD failed schema=#{filename} exception=#{inspect(exception.__struct__)}")
      {:error, :invalid_schema}
  end

  defp validate_projection(projection, schema) do
    config = Application.get_env(:tigoo_server, :fe_authentication, [])
    executable = Keyword.get(config, :xmllint_path, "xmllint")
    directory = Path.join(System.tmp_dir!(), "tigoo-fe-xsd-" <> Base.url_encode64(:crypto.strong_rand_bytes(18), padding: false))
    File.mkdir!(directory)
    try do
      File.chmod!(directory, 0o700)
      path = Path.join(directory, "document.xml")
      File.write!(path, projection, [:exclusive])
      File.chmod!(path, 0o600)
      # xmerl's regexp engine does not implement the XSD \w class used by
      # DGII's email type. libxml2 handles the official schema unchanged.
      Command.run!(executable, ["--nonet", "--noout", "--schema", schema, path], 5000)
    after
      File.rm_rf(directory)
    end
  end

  defp project_root({name, attrs, children}, names) do
    children = Enum.map(children, fn
      {tag, _, _} = node ->
        if List.last(String.split(tag, ":")) == "Signature" do
          element("Signature", [{"xmlns", @ds}], [])
        else
          project(node, names)
        end
      text when is_binary(text) -> characters(text)
    end)

    check_name!(name, attrs, names)
    element(name, [], children)
  end

  defp project({name, attrs, children}, names) do
    check_name!(name, attrs, names)
    element(name, [], Enum.map(children, fn
      {_, _, _} = node -> project(node, names)
      text when is_binary(text) -> characters(text)
    end))
  end

  defp check_name!(name, attrs, names) do
    true = MapSet.member?(names, name) and not String.contains?(name, ":")
    true = Enum.all?(attrs, fn
      {"xmlns", ""} -> true
      {"xmlns:" <> _, _} -> true
      _ -> false
    end)
  end
end
