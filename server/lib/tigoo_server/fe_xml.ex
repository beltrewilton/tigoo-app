defmodule TigooServer.FeXml do
  @moduledoc false

  import Saxy.XML, only: [element: 3, characters: 1]
  require Logger

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
    task = Task.Supervisor.async_nolink(TigooServer.TaskSupervisor, fn ->
      try do
        schema = Application.app_dir(:tigoo_server, "priv/fe/xsd/" <> filename)
        # Only schema-defined element names reach xmerl, which creates atoms.
        # XMLDSig is checked against the original bytes by xmlsec1 separately.
        names = Regex.scan(~r/\bname\s*=\s*["']([^"']+)["']/, File.read!(schema), capture: :all_but_first)
          |> List.flatten() |> MapSet.new()
        projection = project_root(document, names) |> Saxy.encode!()
        {parsed, []} = :xmerl_scan.string(String.to_charlist(projection), quiet: true)

        case :xmerl_xsd.process_validate(String.to_charlist(schema), parsed) do
          {:error, errors} ->
            log_schema_failure(filename, :validation, errors)
            {:error, :invalid_schema}
          {_validated, _state} -> :ok
        end
      rescue
        exception in File.Error ->
          Logger.error("FE XSD failed schema=#{filename} reason=schema_file_unavailable action=#{exception.action}")
          {:error, :verifier_unavailable}
        exception ->
          location = case __STACKTRACE__ do
            [{module, function, _arity, metadata} | _] ->
              "#{inspect(module)}.#{function}:#{Keyword.get(metadata, :line, 0)}"
            _ -> "unknown"
          end

          Logger.error("FE XSD failed schema=#{filename} exception=#{inspect(exception.__struct__)} at=#{location}")
          {:error, :invalid_schema}
      catch
        :exit, reason ->
          log_schema_failure(filename, :exit, reason)
          {:error, :invalid_schema}
      end
    end)

    case Task.yield(task, 5000) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> result
      _ -> {:error, :verifier_unavailable}
    end
  end

  defp log_schema_failure(filename, stage, reason) do
    # Keep only diagnostic atoms; xmerl errors can embed the original XML tree
    # and values, which must not be written to the application log.
    codes = reason |> error_codes() |> Enum.uniq() |> Enum.take(20)
    Logger.error("FE XSD failed schema=#{filename} stage=#{stage} codes=#{inspect(codes)}")
    Enum.each(pattern_errors(reason), fn pattern ->
      Logger.error("FE XSD pattern mismatch schema=#{filename} pattern=#{inspect(pattern)}")
    end)
  end

  defp pattern_errors({:pattern_mismatch, _value, pattern}), do: [to_string(pattern)]
  defp pattern_errors(value) when is_tuple(value), do: value |> Tuple.to_list() |> Enum.flat_map(&pattern_errors/1)
  defp pattern_errors(value) when is_list(value), do: Enum.flat_map(value, &pattern_errors/1)
  defp pattern_errors(_), do: []

  defp error_codes(value) when is_atom(value), do: [value]
  defp error_codes(value) when is_tuple(value), do: value |> Tuple.to_list() |> Enum.flat_map(&error_codes/1)
  defp error_codes(value) when is_list(value), do: Enum.flat_map(value, &error_codes/1)
  defp error_codes(_), do: []

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
