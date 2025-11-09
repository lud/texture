defmodule Texture.UriTemplate do
  alias Texture.UriTemplate.Matcher
  alias Texture.UriTemplate.Renderer
  alias Texture.UriTemplate.TemplateMatchError

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

  @spec parse!(binary) :: t
  def parse!(data) do
    case parse(data) do
      {:ok, t} -> t
      {:error, {:invalid_value, rest}} -> raise ArgumentError, "invalid template, syntax error before: #{inspect(rest)}"
    end
  end

  defp post_parse(parts) do
    parts
    |> post_parse_literals()
    |> Enum.map(&post_parse_part/1)
  end

  defp post_parse_literals(parts) do
    parts
    |> Enum.chunk_by(fn
      {:literals, _} -> true
      _ -> false
    end)
    |> Enum.flat_map(fn
      [{:literals, _} | _] = lits -> [{:lit, join_literals(lits)}]
      parts -> parts
    end)
  end

  defp join_literals(literals) do
    Enum.reduce(literals, <<>>, fn
      {:literals, c}, acc when is_integer(c) -> <<acc::binary, c>>
      {:literals, {:ucschar, [c]}}, acc -> <<acc::binary, c::utf8>>
      {:literals, {:iprivate, [c]}}, acc -> <<acc::binary, c::utf8>>
      {:literals, {:pct_encoded, graphemes}}, acc -> <<acc::binary, Enum.join(graphemes)::binary>>
    end)
  end

  defp post_parse_part(part) do
    case part do
      {:lit, _} = lit ->
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

  This implementations made opinionated choices in regard to the RFC 6570
  specification:

  * Rendering has partial support for list of tuples. Such lists will be
    rendered as maps, but empty lists are still condireded undefined values.
  * Also note that literal parts of the template (everything that is not in `{`
    `}` will be returned as-is, whereas it should be percent-encoded.
  * Using explode (as in `{var*}`) with a scalar value will wrap the value in a
    list. Tuples are not supported.
  """
  @spec render(t, %{optional(atom) => term, optional(binary) => term}) :: binary
  def render(%__MODULE__{} = t, params) do
    Renderer.render(t, params)
  end

  @doc """
  Extracts variables from a URL based on a parsed URI template.

  Returns `{:ok, map}` on success or `{:error, exception}` on failure.

  See `match!/2` for examples and detailed documentation.
  """
  @spec match(t, binary) :: {:ok, %{binary => term}} | {:error, term}
  def match(%__MODULE__{} = t, url) do
    {:ok, Matcher.match!(t, url)}
  rescue
    e in TemplateMatchError -> {:error, e}
  end

  @doc """
  Same as `match/2` but raises `Texture.UriTemplate.TemplateMatchError` on failure.

  This implementation has **limited support** and is designed for
  straightforward, simple templates. Use it for basic path and query parameter
  extraction. Rendering is a lossy operation, so the reverse operation cannot
  always regenerate original values.

  ## Supported Operators

  Only three operators are supported:

  * **Default** (no operator): `{foo}`
  * **Path segment** (`/`): `{/foo}`
  * **Query** (`?`): `{?foo}`

  Other operators like `+`, `#`, `.`, `;`, `&` are **not supported** for
  matching.

  ## Basic Examples

      iex> t = Texture.UriTemplate.parse!("http://example.com/{foo}")
      iex> Texture.UriTemplate.match!(t, "http://example.com/hello")
      %{"foo" => "hello"}

      iex> t = Texture.UriTemplate.parse!("http://example.com/{foo}/{bar}")
      iex> Texture.UriTemplate.match!(t, "http://example.com/hello/world")
      %{"foo" => "hello", "bar" => "world"}

      iex> t = Texture.UriTemplate.parse!("http://example.com{/version,resource}")
      iex> Texture.UriTemplate.match!(t, "http://example.com/v1/users")
      %{"version" => "v1", "resource" => "users"}

      iex> t = Texture.UriTemplate.parse!("http://example.com/api{?foo,bar}")
      iex> Texture.UriTemplate.match!(t, "http://example.com/api?foo=1&bar=2")
      %{"foo" => "1", "bar" => "2"}

  ## More Complex Examples

      iex> t = Texture.UriTemplate.parse!("http://example.com/search{?foo*,bar}")
      iex> Texture.UriTemplate.match!(t, "http://example.com/search?foo=1&foo=2&foo=3&bar=hello")
      %{"foo" => ["1", "2", "3"], "bar" => "hello"}

      iex> t = Texture.UriTemplate.parse!("http://example.com/api{?map*,simple}")
      iex> Texture.UriTemplate.match!(t, "http://example.com/api?a=1&b=&simple=value")
      %{"map" => %{"a" => "1", "b" => ""}, "simple" => "value"}

  ## Behavior Details

  ### Empty Values

  * Empty parameter values return `nil`
  * Lists containing empty strings preserve them: `["", "b", ""]`
  * Empty values in maps preserve empty keys or values

  ### Value Types

  * All extracted values are strings (including numeric-like values)
  * Unicode characters are properly decoded
  * Percent-encoding is handled automatically

  ### List Matching

  * Lists are comma-separated in default and query operators
  * With other operators,lLists are comma-separated only when the parameter is
    not exploded .
  * With multiple parameters, the last accumulates remaining values as a list
  * Insufficient values assign `nil` to remaining parameters

  Examples:

      # Lists with comma separator
      iex> t = Texture.UriTemplate.parse!("{foo}")
      iex> Texture.UriTemplate.match!(t, "1,2,3")
      %{"foo" => ["1", "2", "3"]}

      # Multiple params share list values
      iex> t = Texture.UriTemplate.parse!("{foo,bar}")
      iex> Texture.UriTemplate.match!(t, "1,2,3")
      %{"foo" => "1", "bar" => ["2", "3"]}

  ### Exploded Parameters (`*`)

  * Exploded lists take all matching items into a list
  * Exploded maps take all `key=value` pairs into a map
  * Non-exploded maps are ambiguous and parsed as lists

  Examples:

      # Path segments with exploded list
      iex> t = Texture.UriTemplate.parse!("{/foo*}")
      iex> Texture.UriTemplate.match!(t, "/a/b/c")
      %{"foo" => ["a", "b", "c"]}

  ### Query Parameters

  * Parameters are matched by name, not position
  * Order doesn't matter for query parameters
  * Duplicate names in exploded lists accumulate into a list
  * First occurrence wins for duplicate non-exploded parameters

  Examples:

  Query parameters (`{?foo,bar*,baz*}`) use a three-phase matching algorithm:

  1. Each non-exploded parameter takes its matching `key=value` pair from the
     URL by name
  2. Exploded parameters that have matching names in the URL collect all
     occurrences into a list (e.g., `foo=1&foo=2` → `["1", "2"]`)
  3. The first exploded parameter that hasn't matched any names takes all
     remaining `key=value` pairs as a map

          iex> t = Texture.UriTemplate.parse!("{?none,simple,items*,rest*,none_expl*}")
          iex> Texture.UriTemplate.match!(t, "?extra=1&other=2&items=a&items=b&simple=value")
          %{
            "none" => nil,
            "simple" => "value",
            "items" => ["a", "b"],
            "rest" => %{"extra" => "1", "other" => "2"},
            "none_expl" => nil
          }

  ### Parameter Skipping

  Extra query parameters that don't match any template variable are silently
  ignored. This allows matching URLs with tracking parameters added by external
  tools

  ### Value Encoding

  * Percent-encoding is handled automatically
  * Unicode characters are properly decoded

  Examples:

      # Percent-encoded values
      iex> t = Texture.UriTemplate.parse!("{foo}")
      iex> Texture.UriTemplate.match!(t, "hello%20world")
      %{"foo" => "hello world"}

      # Query with empty parameter
      iex> t = Texture.UriTemplate.parse!("{?foo,bar}")
      iex> Texture.UriTemplate.match!(t, "?foo=&bar=value")
      %{"foo" => nil, "bar" => "value"}

  ### Duplicate Parameters

  When the same parameter name appears multiple times in a template, the first
  occurrence is preserved. This ensures path parameters are not overridden by
  query parameters.

  Example:

      # Duplicate parameter names (first wins)
      iex> t = Texture.UriTemplate.parse!("{foo}/{foo}")
      iex> Texture.UriTemplate.match!(t, "first/second")
      %{"foo" => "first"}

  ### Error Cases

  Raises `Texture.UriTemplate.TemplateMatchError` when:

  * Non-exploded parameter receives dict syntax unexpectedly
  * Extra path segment values don't match template structure
  * Invalid parameter syntax (e.g., `foo==bar`)
  * Lists treated as keys in wrong context
  """
  @spec match!(t, binary) :: %{binary => term}
  def match!(%__MODULE__{} = t, url) do
    Matcher.match!(t, url)
  end
end
