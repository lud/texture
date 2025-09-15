defmodule Texture.UriTemplate do
  @moduledoc false
  @external_resource "priv/grammars/uri-template.abnf"

  @enforce_keys [:parts, :raw]
  defstruct @enforce_keys

  use AbnfParsec,
    abnf_file: "priv/grammars/uri-template.abnf",
    unbox: ["URI-Template", "varchar", "op-level2", "op-level3", "op-reserve", "modifier-level4"],
    unwrap: ["literals", "explode"],
    untag: ["max-length"],
    ignore: []

  @type t :: %__MODULE__{parts: term, raw: binary}

  @doc false
  @spec parse(binary) :: {:ok, t} | {:error, term}
  def parse(data) do
    case uri_template(data) do
      {:ok, parts, "", _, _, _} -> {:ok, %__MODULE__{parts: parts, raw: data}}
      _ -> {:error, :invalid}
    end
  end

  @spec generate_uri(t, %{optional(atom) => term, optional(binary) => term}) :: binary
  def generate_uri(%__MODULE__{parts: parts}, params) do
    params =
      Map.new(params, fn
        {key, value} when is_binary(key) -> {key, value}
        {key, value} when is_atom(key) -> {render_key(key), value}
      end)

    IO.iodata_to_binary(do_generate_uri(parts, params))
  end

  defp do_generate_uri(parts, params) do
    Enum.map(parts, fn item -> render_part(item, params) end)
  end

  defp render_part({:literals, n}, _) do
    n
  end

  defp render_part({:expression, ["{", {:variable_list, varlist}, "}"]}, params) do
    Enum.map(varlist, fn {:varspec, vspec} -> render_var(vspec, params, :allow_unreserved) end)
  end

  defp render_part(
         {:expression, ["{", {:operator, [op]}, {:variable_list, varlist}, "}"]},
         params
       ) do
    render_variable_list_kv(op, varlist, params)
  end

  defp render_variable_list_kv(";", varlist, params) do
    varlist
    |> Enum.flat_map(fn
      {:varspec, vspec} -> render_kvs(vspec, params, _enforce_eq? = false, :allow_unreserved)
      "," -> []
    end)
    |> Enum.map(&[";", &1])
  end

  defp render_variable_list_kv(op, varlist, params) when op in ["?", "&"] do
    varlist
    |> Enum.flat_map(fn
      {:varspec, vspec} -> render_kvs(vspec, params, _enforce_eq? = true, :allow_unreserved)
      "," -> []
    end)
    |> Enum.intersperse([?&])
    |> prefix_nonempty_list(op)
  end

  defp render_variable_list_kv("#", varlist, params) do
    varlist
    |> Enum.flat_map(fn
      {:varspec, vspec} -> render_var(vspec, params, :allow_reserved_unreserved)
      "," -> []
    end)
    |> Enum.intersperse(?,)
    |> prefix_nonempty_list(?#)
  end

  defp render_variable_list_kv("+", varlist, params) do
    varlist
    |> Enum.flat_map(fn
      {:varspec, vspec} -> render_var(vspec, params, :allow_reserved_unreserved)
      "," -> []
    end)
    |> Enum.intersperse(?,)
  end

  defp render_variable_list_kv(op, varlist, params) when op in ["/", "."] do
    varlist
    |> Enum.flat_map(fn
      {:varspec, vspec} -> render_var(vspec, params, :allow_unreserved)
      "," -> []
    end)
    |> Enum.intersperse(op)
    |> prefix_nonempty_list(op)
  end

  defp prefix_nonempty_list([], _) do
    []
  end

  defp prefix_nonempty_list(list, prefix) do
    [prefix, list]
  end

  defp render_kvs([{:varname, letters}], params, enforce_eq?, special_chars) do
    name = Enum.join(letters)

    case Map.fetch(params, name) do
      {:ok, []} -> []
      {:ok, value} -> [render_kv(name, enforce_eq?, render_value(value, special_chars))]
      :error -> []
    end
  end

  defp render_kvs([{:varname, letters}, {:explode, "*"}], params, enforce_eq?, special_chars) do
    name = Enum.join(letters)

    case Map.fetch!(params, name) do
      list when is_list(list) ->
        Enum.map(list, &[render_kv(name, enforce_eq?, render_value(&1, special_chars))])

      map when map_size(map) > 0 ->
        Enum.map(map, fn {key, value} ->
          [render_kv(render_key(key), enforce_eq?, render_value(value, special_chars))]
        end)

      %{} ->
        []
    end
  end

  defp render_kv(name, true, "") do
    [name, ?=]
  end

  defp render_kv(name, false, "") do
    name
  end

  defp render_kv(name, _, rendered_value) do
    [name, ?=, rendered_value]
  end

  defp render_var([{:varname, letters}], params, special_chars) do
    name = Enum.join(letters)

    case Map.fetch(params, name) do
      {:ok, value} -> [render_value(value, special_chars)]
      :error -> []
    end
  end

  defp render_var([{:varname, letters}, {:explode, "*"}], params, special_chars) do
    name = Enum.join(letters)

    case Map.fetch!(params, name) do
      list when is_list(list) -> Enum.map(list, &render_value(&1, special_chars))
    end
  end

  defp render_var([{:varname, letters}, {:prefix, [_, n_aslist]}], params, special_chars) do
    {max_len, ""} = Integer.parse(List.to_string(n_aslist))
    name = Enum.join(letters)

    case Map.fetch!(params, name) do
      value -> [render_value(value, {special_chars, max_len})]
    end
  end

  defp render_value(list, special_chars) when is_list(list) do
    Enum.map_intersperse(list, ?,, &render_value(&1, special_chars))
  end

  defp render_value(value, special_chars) do
    value
    |> value_to_string()
    |> encode_value(special_chars)
  end

  defp value_to_string(str) when is_binary(str) do
    str
  end

  defp value_to_string(atom) when is_atom(atom) do
    Atom.to_string(atom)
  end

  defp value_to_string(other) do
    Kernel.to_string(other)
  end

  defp encode_value(value, {special_chars, max_len}) do
    encode_value(String.slice(value, 0, max_len), special_chars)
  end

  defp encode_value(value, :allow_unreserved) do
    URI.encode(value, &URI.char_unreserved?/1)
  end

  defp encode_value(value, :allow_reserved_unreserved) do
    URI.encode(value, &URI.char_unescaped?/1)
  end

  defp render_key(key) do
    render_value(key, :allow_unreserved)
  end
end
