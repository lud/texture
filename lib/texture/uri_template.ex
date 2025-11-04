defmodule Texture.UriTemplate do
  @moduledoc ~S"""
  URI Template parser implementation following RFC 6570 (levels 1–4).

  Parsing returns a `%Texture.UriTemplate{}` struct. Use `render/2` to expand it
  with variable values provided either as atom or binary keys.

  ## Parsing

      {:ok, template} = Texture.UriTemplate.parse("/users/{id}")
      %Texture.UriTemplate{}

  An invalid template returns an error tuple:

      iex> Texture.UriTemplate.parse("/x/{not_closed")
      {:error, {:invalid_value, "{not_closed"}}

  ## Rendering

  Provide a map whose keys are either atoms or binaries. Values are coerced
  to strings; lists and exploded maps are supported per RFC 6570.

      iex> {:ok, t} = Texture.UriTemplate.parse("https://ex.com{/ver}{/res*}{?q,lang}{&page}")
      iex> Texture.UriTemplate.render(t, %{ver: "v1", res: ["users", 42], q: "café", lang: :fr, page: 2})
      "https://ex.com/v1/users/42?q=caf%C3%A9&lang=fr&page=2"

  Reserved expansion keeps reserved characters (e.g. '+'):

      iex> {:ok, t} = Texture.UriTemplate.parse("/files{+path}")
      iex> Texture.UriTemplate.render(t, %{path: "/a/b c"})
      "/files/a/b%20c"

  Simple expansion percent-encodes reserved characters:

      iex> {:ok, t} = Texture.UriTemplate.parse("/files/{path}")
      iex> Texture.UriTemplate.render(t, %{path: "/a/b c"})
      "/files/%2Fa%2Fb%20c"

  Exploded list path segments:

      iex> {:ok, t} = Texture.UriTemplate.parse("/api{/segments*}")
      iex> Texture.UriTemplate.render(t, %{segments: ["v1", "users", 42]})
      "/api/v1/users/42"

  Query continuation & omission of undefined variables:

      iex> {:ok, t} = Texture.UriTemplate.parse("?fixed=1{&x,y}")
      iex> Texture.UriTemplate.render(t, %{x: 2})
      "?fixed=1&x=2"

  Fragment expansion with unicode & prefix modifier:

      iex> {:ok, t} = Texture.UriTemplate.parse("{#frag:6}")
      iex> Texture.UriTemplate.render(t, %{frag: "café-bar"})
      "#caf%C3%A9-b"

  Empty list omits expression:

      iex> {:ok, t} = Texture.UriTemplate.parse("/s{?list}")
      iex> Texture.UriTemplate.render(t, %{list: []})
      "/s"

  ## Notes

  * Undefined variables are silently omitted.
  * Empty string values may contribute a key without '=' (for certain operators like ';').
  * Order of exploded map query parameters is not guaranteed (maps are unordered).
  """
  @external_resource "priv/grammars/uri-template.abnf"

  @enforce_keys [:parts, :raw]
  defstruct @enforce_keys

  use AbnfParsec,
    abnf_file: "priv/grammars/uri-template.abnf",
    unbox: ["URI-Template", "varchar", "op-level2", "op-level3", "op-reserve", "modifier-level4"],
    unwrap: ["literals", "explode"],
    untag: ["max-length"],
    ignore: [],
    private: true

  @type t :: %__MODULE__{parts: term, raw: binary}

  @doc """
  Parses an URI template into an internal representation.
  """
  @spec parse(binary) :: {:ok, t} | {:error, term}
  def parse(data) do
    case uri_template(data) do
      {:ok, parts, "", _, _, _} -> {:ok, %__MODULE__{parts: post_parse(parts), raw: data}}
      {:ok, _, rest, _, _, _} -> {:error, {:invalid_value, rest}}
    end
  end

  defp post_parse(parts) do
    Enum.map(parts, &post_parse_part/1)
  end

  defp post_parse_part(part) do
    case part do
      {:literals, _} = lit ->
        lit

      {:expression, ["{" | expr]} ->
        {"}", expr} = List.pop_at(expr, -1)

        {op, varlist} =
          case expr do
            [operator: [op], variable_list: varlist] -> {op, post_parse_varlist(varlist)}
            [variable_list: varlist] -> {:default, post_parse_varlist(varlist)}
          end

        {:expr, op, varlist}
    end
  end

  defp post_parse_varlist(elems) do
    Enum.flat_map(elems, fn
      "," ->
        []

      {:varspec, [varname: varname]} ->
        [{:var, Enum.join(varname), nil}]

      {:varspec, [varname: varname, explode: "*"]} ->
        [{:var, Enum.join(varname), :explode}]

      {:varspec, [varname: varname, prefix: [":", n_aslist]]} ->
        {max_len, ""} = Integer.parse(List.to_string(n_aslist))
        [{:var, Enum.join(varname), {:prefix, max_len}}]
    end)
  end

  @doc """
  Renders a template given its internal representation and a map of parameters.

  Rendering has partial support for list of tuples. Such lists will be rendered
  as maps, but empty lists are still condireded undefined values.

  Also note that literal parts of the template (everything that is not in `{`
  `}` will be returned as-is, whereas it should be percent-encoded.
  """
  @spec render(t, %{optional(atom) => term, optional(binary) => term}) :: binary
  def render(%__MODULE__{parts: parts}, params) do
    params =
      Map.new(params, fn
        {key, value} when is_binary(key) -> {key, value}
        {key, value} when is_atom(key) -> {Atom.to_string(key), value}
      end)

    IO.iodata_to_binary(do_render(parts, params))
  end

  defp do_render(parts, params) do
    Enum.map(parts, fn item -> render_part(item, params) end)
  end

  defp render_part({:literals, lit}, _) do
    case lit do
      c when is_integer(c) -> c
      {:ucschar, [c]} -> <<c::utf8>>
      {:iprivate, [c]} -> <<c::utf8>>
      {:pct_encoded, graphemes} -> graphemes
    end
  end

  defp render_part({:expr, op, varlist}, params) do
    render_expr(op, varlist, params)
  end

  defp render_expr(op, varlist, params) do
    # dict_mode
    # * :always => turn lists and map into key=value strings, with a `=` for empty values, like a=&b=2
    # * :nonempty => turn lists and map into key=value strings, without a `=` for empty values like a&b=2
    # * :dicts => do not encode as dict, return "2", EXCEPT for map or keywords

    {escape, dict_mode, c_intersperse, c_listprefix} =
      case op do
        c when c in [";"] -> {:allow_unreserved, :nonempty, op, op}
        c when c in ["?", "&"] -> {:allow_unreserved, :always, ?&, op}
        c when c in ["/", "."] -> {:allow_unreserved, :dicts, op, op}
        "#" -> {:allow_reserved_unreserved, :dicts, ?,, ?#}
        "+" -> {:allow_reserved_unreserved, :dicts, ?,, nil}
        :default -> {:allow_unreserved, :dicts, ?,, nil}
      end

    values = render_varlist(varlist, escape, dict_mode, params)

    values = Enum.intersperse(values, c_intersperse)

    case values do
      [_ | _] when c_listprefix != nil -> [c_listprefix | values]
      _ -> values
    end
  end

  # With those operators we will include the keys in the rendered vars
  defp render_varlist(varlist, escape, dict_mode, params) do
    Enum.flat_map(varlist, &render_var(&1, escape, dict_mode, params))
  end

  # Render var always returns a list, so we can merge normal values and explode*
  # values in a list at the same level (for further intersperse)

  defp render_var({:var, name, :explode}, escape, dict_mode, params) do
    case fetch_param(params, name) do
      {:ok, value} ->
        value
        |> explode_value(dict_mode, name)
        |> render_pairs(escape, dict_mode)

      :error ->
        []
    end
  end

  defp render_var({:var, name, nil}, escape, dict_mode, params) do
    case fetch_param(params, name) do
      {:ok, value} -> render_pairs([{name, value}], escape, dict_mode)
      :error -> []
    end
  end

  defp render_var({:var, name, {:prefix, max_len}}, escape, dict_mode, params) do
    case fetch_param(params, name) do
      {:ok, value} -> render_pairs([{name, value}], {escape, max_len}, dict_mode)
      :error -> []
    end
  end

  defp fetch_param(params, key) do
    # https://www.rfc-editor.org/rfc/rfc6570.html#section-2.3
    #
    # * A variable defined as a list value is considered undefined if the list
    #   contains zero members.
    # * A variable defined as an associative array of (name, value) pairs is
    #   considered undefined if the array contains zero members or if all member
    #   names in the array are associated with undefined values.
    case Map.fetch(params, key) do
      {:ok, list} when is_list(list) ->
        check_undef_compound(list)

      {:ok, map} when is_map(map) ->
        check_undef_compound(map)

      {:ok, value} ->
        case undef?(value) do
          true -> :error
          false -> {:ok, value}
        end

      :error ->
        :error
    end
  end

  defp check_undef_compound(list) when is_list(list) do
    case Enum.reject(list, &undef?/1) do
      [] -> :error
      list -> {:ok, list}
    end
  end

  defp check_undef_compound(map) when is_map(map) do
    case Map.reject(map, fn {_, v} -> undef?(v) end) do
      empty when map_size(empty) == 0 -> :error
      %_{} = empty when map_size(empty) == 1 -> :error
      map -> {:ok, map}
    end
  end

  defp undef?(nil) do
    true
  end

  defp undef?([]) do
    true
  end

  defp undef?(empty_map) when empty_map == %{} do
    true
  end

  defp undef?(_) do
    false
  end

  defp explode_value(list, :dicts, _default_key) when is_list(list) do
    Enum.map(list, fn
      {k, v} -> {:pair, k, v}
      v -> v
    end)
  end

  defp explode_value(list, _, default_key) when is_list(list) do
    Enum.map(list, fn
      {k, v} -> {k, v}
      v -> {default_key, v}
    end)
  end

  defp explode_value(map, _, _default_key) when is_map(map) do
    Map.to_list(map)
  end

  defp render_pairs(list, escape, dict_mode) when is_list(list) do
    case dict_mode do
      :dicts ->
        Enum.flat_map(list, fn
          {_k, v} -> [render_value(v, escape)]
          {:pair, k, v} -> [[render_key(k), ?=, render_value(v, escape)]]
          v -> [render_value(v, escape)]
        end)

      :always ->
        Enum.map(list, fn {k, v} -> [render_kv(k, v, escape, :enforce_sep)] end)

      :nonempty ->
        Enum.map(list, fn {k, v} -> [render_kv(k, v, escape, :nonempty)] end)
    end
  end

  defp render_kv(k, v, escape, :enforce_sep) do
    [render_key(k), ?=, render_value(v, escape)]
  end

  defp render_kv(k, v, escape, :nonempty) do
    case render_value(v, escape) do
      "" -> render_key(k)
      str -> [render_key(k), ?=, str]
    end
  end

  defp render_value(list, escape) when is_list(list) do
    Enum.map_intersperse(list, ?,, fn
      # Support for keyword list
      {k, v} ->
        v =
          v
          |> value_to_string()
          |> encode_value(escape)

        [render_key(k), ?,, v]

      v ->
        v
        |> value_to_string()
        |> encode_value(escape)
    end)
  end

  defp render_value(map, escape) when is_map(map) do
    Enum.map_intersperse(map, ?,, fn {k, v} ->
      v =
        v
        |> value_to_string()
        |> encode_value(escape)

      [render_key(k), ?,, v]
    end)
  end

  defp render_value(value, {escape, max_len}) do
    value
    |> value_to_string()
    |> String.slice(0..(max_len - 1))
    |> encode_value(escape)
  end

  defp render_value(value, escape) do
    value
    |> value_to_string()
    |> encode_value(escape)
  end

  defp value_to_string(str) when is_binary(str) do
    str
  end

  defp value_to_string(nil) do
    ""
  end

  defp value_to_string(atom) when is_atom(atom) do
    case Atom.to_string(atom) do
      "Elixir." <> rest -> rest
      all -> all
    end
  end

  defp value_to_string(other) do
    Kernel.to_string(other)
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
