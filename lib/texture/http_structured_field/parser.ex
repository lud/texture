# credo:disable-for-this-file Credo.Check.Readability.FunctionNames
# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Texture.HttpStructuredField.Parser do
  alias Texture.HttpStructuredField.Parser.Error

  @moduledoc false

  defguard is_ALPHA(c) when c in ?a..?z or c in ?A..?Z
  defguard is_DIGIT(c) when c in ?0..?9
  defguard is_lcalpha(c) when c in ?a..?z
  defguard is_OWS(c) when c in [?\s, ?\t]

  defguard is_tchar(c)
           when is_ALPHA(c) or
                  is_DIGIT(c) or
                  c in [?_, ?-, ?!, ?., ?', ?*, ?&, ?#, ?%, ?`, ?^, ?+, ?|, ?~, ?$]

  defguard is_EOE(c) when c in [?;, ?,, ?\s, ?\t, ?)]

  defguard is_base64(c) when is_ALPHA(c) or is_DIGIT(c) or c in [?+, ?/]

  defguard is_lc_hexdig(c) when is_DIGIT(c) or c in ?a..?f

  # Maximum number of digits mandated by RFC 9651. Numbers with more digits are
  # invalid.
  @max_integer_digits 15
  @max_decimal_integer_digits 12
  @max_decimal_fractional_digits 3

  def parse_dict(buf) do
    {:ok, parse_dict!(buf), ""}
  rescue
    e in Error -> {:error, e}
  end

  def parse_dict!(input) do
    parse_dict(input, [])
  rescue
    e in Error -> reraise(%{e | value: input}, __STACKTRACE__)
  end

  defp parse_dict(buf, acc) do
    case parse_key(buf) do
      {:bool_true, key, buf} ->
        {item, buf} = collect_parameters({:boolean, true}, buf)
        continue_dict(buf, [{key, item} | acc])

      {:ok, key, <<?=, buf::binary>>} ->
        {item, buf} = parse_item_keep_whitespace_or_inner_list(buf)
        continue_dict(buf, [{key, item} | acc])
    end
  end

  defp continue_dict(buf, acc) do
    buf = skip_ws(buf)

    case buf do
      <<?,, buf::binary>> -> parse_dict(skip_ws(buf), acc)
      <<>> -> finalize_dict(acc)
      buf -> fail(:expected_delimiter, buf)
    end
  end

  defp finalize_dict(acc) do
    dedup_keys(acc)
  end

  def parse_list(buf) do
    {:ok, parse_list!(buf), ""}
  rescue
    e in Error -> {:error, e}
  end

  def parse_list!(input) do
    parse_list(input, [])
  rescue
    e in Error -> reraise(%{e | value: input}, __STACKTRACE__)
  end

  defp parse_list(buf, acc) do
    {item, buf} = parse_item_keep_whitespace_or_inner_list(buf)
    buf = skip_ws(buf)

    case buf do
      <<?,, buf::binary>> -> parse_list(skip_ws(buf), [item | acc])
      <<>> -> finalize_list([item | acc])
      buf -> fail(:expected_delimiter, buf)
    end
  end

  defp finalize_list(acc) do
    :lists.reverse(acc)
  end

  defp parse_inner_list(<<?(, buf::binary>>) do
    parse_inner_list(skip_ws(buf), [])
  end

  defp parse_inner_list(<<?), buf::binary>>, acc) do
    case buf do
      <<c, _::binary>> when is_EOE(c) -> {{:inner_list, :lists.reverse(acc)}, buf}
      <<>> -> {{:inner_list, :lists.reverse(acc)}, buf}
      buf -> fail(:expected_eoe, buf)
    end
  end

  defp parse_inner_list(buf, acc) do
    {item, buf} = parse_item_keep_whitespace(buf)
    buf = skip_expect_ws_or_lookahead_closing_paren(buf)
    parse_inner_list(buf, [item | acc])
  end

  # * If we find whitespace, then we skip it and we will arrive at the ')' or a
  #   next item to parse.
  # * If there is directly a ')' we do not consume it to arrive at it on the
  #   next loop of parse_inner_list/2, but we do not expect any whitespace
  defp skip_expect_ws_or_lookahead_closing_paren(buf)

  defp skip_expect_ws_or_lookahead_closing_paren(<<c, buf::binary>>) when is_OWS(c) do
    skip_ws(buf)
  end

  # Keep the closing paren in the bufer
  defp skip_expect_ws_or_lookahead_closing_paren(<<?\), _::binary>> = buf) do
    buf
  end

  defp skip_expect_ws_or_lookahead_closing_paren(buf) do
    fail(:expected_whitespace, buf)
  end

  def parse_item(buf) do
    {:ok, parse_item!(buf), ""}
  rescue
    e in Error -> {:error, e}
  end

  def parse_item!(input) do
    {item, buf} = parse_item_keep_whitespace(input)

    case skip_ws(buf) do
      "" -> item
      rest -> fail(:expected_delimiter, rest)
    end
  rescue
    e in Error -> reraise(%{e | value: input}, __STACKTRACE__)
  end

  defp parse_item_keep_whitespace(buf) do
    {item, buf} = parse_bare_item(buf)
    collect_parameters(item, buf)
  end

  defp parse_item_keep_whitespace_or_inner_list(<<?(, _::binary>> = buf) do
    {inner, buf} = parse_inner_list(buf)
    collect_parameters(inner, buf)
  end

  defp parse_item_keep_whitespace_or_inner_list(buf) do
    parse_item_keep_whitespace(buf)
  end

  defp collect_parameters({tag, value}, buf) do
    {parameters, buf} = take_ws_parameters(buf, [])
    {{tag, value, parameters}, buf}
  end

  # Bare item parsers below are used to "peek" at the buffer and try the next
  # possible item type, so they return result tuples instead of raising.

  defp parse_bare_item(buf) do
    with {:error, _} <- parse_decimal(buf),
         {:error, _} <- parse_integer(buf),
         {:error, _} <- parse_string(buf),
         {:error, _} <- parse_boolean(buf),
         {:error, _} <- parse_token(buf),
         {:error, _} <- parse_byte_sequence(buf),
         {:error, _} <- parse_date(buf),
         {:error, _} <- parse_display_string(buf) do
      fail(:invalid_value, buf)
    else
      {:ok, item, buf} -> {item, buf}
    end
  end

  defp parse_date(<<?@, buf::binary>>) do
    case parse_integer(buf) do
      {:ok, {:integer, seconds}, buf} -> {:ok, {:date, seconds}, buf}
      {:error, _} = err -> err
    end
  end

  defp parse_date(buf) do
    error(:invalid_date, buf)
  end

  defp parse_display_string(<<?%, ?", buf::binary>> = all) do
    case take_display_string(buf, []) do
      {:ok, decoded, buf} ->
        if String.valid?(decoded) do
          {:ok, {:display_string, decoded}, buf}
        else
          error(:invalid_display_string, all)
        end

      {:error, _} = err ->
        err
    end
  end

  defp parse_display_string(buf) do
    error(:invalid_display_string, buf)
  end

  defp take_display_string(<<?", buf::binary>>, acc) do
    case buf do
      <<c, _::binary>> when is_EOE(c) -> {:ok, :erlang.list_to_binary(:lists.reverse(acc)), buf}
      <<>> -> {:ok, :erlang.list_to_binary(:lists.reverse(acc)), buf}
      _ -> error(:expected_delimiter, buf)
    end
  end

  defp take_display_string(<<?%, hi, lo, buf::binary>>, acc)
       when is_lc_hexdig(hi) and is_lc_hexdig(lo) do
    take_display_string(buf, [hexdig_value(hi) * 16 + hexdig_value(lo) | acc])
  end

  defp take_display_string(<<c, buf::binary>>, acc) when c in 0x20..0x7E and c != ?% do
    take_display_string(buf, [c | acc])
  end

  defp take_display_string(<<_, _::binary>> = all, _acc) do
    error(:invalid_display_string, all)
  end

  defp take_display_string(<<>>, _acc) do
    error(:expected_delimiter, <<>>)
  end

  defp hexdig_value(c) when is_DIGIT(c) do
    c - ?0
  end

  defp hexdig_value(c) do
    c - ?a + 10
  end

  defp parse_integer(<<?-, c, buf::binary>>) when is_DIGIT(c) do
    case take_integer(buf, [c, ?-], 1) do
      {:ok, digits, buf} -> {:ok, {:integer, finalize_integer(digits)}, buf}
      {:error, _} = err -> err
    end
  end

  defp parse_integer(<<c, buf::binary>>) when is_DIGIT(c) do
    case take_integer(buf, [c], 1) do
      {:ok, digits, buf} -> {:ok, {:integer, finalize_integer(digits)}, buf}
      {:error, _} = err -> err
    end
  end

  defp parse_integer(buf) do
    error(:invalid_integer, buf)
  end

  defp take_integer(<<c, buf::binary>>, acc, n) when is_DIGIT(c) and n < @max_integer_digits do
    take_integer(buf, [c | acc], n + 1)
  end

  defp take_integer(buf, acc, _n) do
    case buf do
      <<c, _::binary>> when is_EOE(c) -> {:ok, :lists.reverse(acc), buf}
      <<>> -> {:ok, :lists.reverse(acc), buf}
      _ -> error(:expected_delimiter, buf)
    end
  end

  defp finalize_integer(digits) do
    :erlang.list_to_integer(digits)
  end

  defp parse_decimal(<<?-, c, buf::binary>>) when is_DIGIT(c) do
    case take_decimal(buf, [c, ?-], _seen_dot? = false, 1) do
      {:ok, [^c, ?-], _} -> error(:expected_dot, buf)
      {:ok, digits, buf} -> {:ok, {:decimal, finalize_decimal(digits)}, buf}
      {:error, _} = err -> err
    end
  end

  defp parse_decimal(<<c, buf::binary>>) when is_DIGIT(c) do
    case take_decimal(buf, [c], false, 1) do
      {:ok, digits, buf} -> {:ok, {:decimal, finalize_decimal(digits)}, buf}
      {:error, _} = err -> err
    end
  end

  defp parse_decimal(buf) do
    error(:invalid_decimal, buf)
  end

  defp take_decimal(<<c, buf::binary>>, acc, false, n)
       when is_DIGIT(c) and n < @max_decimal_integer_digits do
    take_decimal(buf, [c | acc], false, n + 1)
  end

  defp take_decimal(<<c, buf::binary>>, acc, true, n)
       when is_DIGIT(c) and n < @max_decimal_fractional_digits do
    take_decimal(buf, [c | acc], true, n + 1)
  end

  defp take_decimal(<<?., c, buf::binary>>, acc, false, _n) when is_DIGIT(c) do
    take_decimal(buf, [c, ?. | acc], true, 1)
  end

  defp take_decimal(buf, acc, true, _n) do
    case buf do
      <<c, _::binary>> when is_EOE(c) -> {:ok, :lists.reverse(acc), buf}
      <<>> -> {:ok, :lists.reverse(acc), buf}
      _ -> error(:expected_delimiter, buf)
    end
  end

  defp take_decimal(buf, _acc, false, _n) do
    error(:invalid_decimal, buf)
  end

  defp finalize_decimal(digits) do
    :erlang.list_to_float(digits)
  end

  defp parse_boolean(<<??, ?0, buf::binary>>) do
    {:ok, {:boolean, false}, buf}
  end

  defp parse_boolean(<<??, ?1, buf::binary>>) do
    {:ok, {:boolean, true}, buf}
  end

  defp parse_boolean(buf) do
    error(:invalid_boolean, buf)
  end

  defp parse_byte_sequence(<<?:, ?:, buf::binary>> = all) do
    case buf do
      <<c, _::binary>> when is_EOE(c) -> {:ok, {:byte_sequence, ""}, buf}
      <<>> -> {:ok, {:byte_sequence, ""}, buf}
      _ -> error(:expected_delimiter, all)
    end
  end

  defp parse_byte_sequence(<<?:, c, buf::binary>> = all) when is_base64(c) do
    case take_byte_sequence(buf, [c]) do
      {:ok, _bin, _buf} = ok -> ok
      {:error, :b64_decode} -> error(:invalid_byte_sequence, all)
      {:error, _} = err -> err
    end
  end

  defp parse_byte_sequence(buf) do
    error(:invalid_byte_sequence, buf)
  end

  defp take_byte_sequence(<<c, buf::binary>>, acc) when is_base64(c) do
    take_byte_sequence(buf, [c | acc])
  end

  defp take_byte_sequence(<<?=, buf::binary>>, acc) do
    # We can just add the padding to the binary. If that character is
    # present in the middle of the b64 string like this: "aGVsbG8=aGVsbG8="
    # it's going to be invalid anyway.
    take_byte_sequence(buf, [?= | acc])
  end

  defp take_byte_sequence(<<?:, buf::binary>>, acc) do
    case buf do
      <<c, _::binary>> when is_EOE(c) -> ok_finalize_byte_sequence(acc, buf)
      <<>> -> ok_finalize_byte_sequence(acc, buf)
      _ -> error(:expected_delimiter, buf)
    end
  end

  defp take_byte_sequence(buf, _) do
    error(:invalid_byte_sequence, buf)
  end

  defp ok_finalize_byte_sequence(rev, buf) do
    b64 = IO.iodata_to_binary(:lists.reverse(rev))

    case Base.decode64(b64) do
      {:ok, value} -> {:ok, {:byte_sequence, value}, buf}
      :error -> {:error, :b64_decode}
    end
  end

  defp parse_string(<<?", buf::binary>>) do
    case take_string(buf, []) do
      {:ok, string, buf} -> {:ok, {:string, string}, buf}
      {:error, _} = err -> err
    end
  end

  defp parse_string(buf) do
    error(:invalid_string, buf)
  end

  defp take_string(<<?", buf::binary>>, acc) do
    case buf do
      <<c, _::binary>> when is_EOE(c) -> {:ok, IO.iodata_to_binary(:lists.reverse(acc)), buf}
      <<>> -> {:ok, IO.iodata_to_binary(:lists.reverse(acc)), buf}
      _ -> error(:expected_delimiter, buf)
    end
  end

  defp take_string(<<?\\, ?\\, buf::binary>>, acc) do
    take_string(buf, ["\\" | acc])
  end

  defp take_string(<<?\\, ?", buf::binary>>, acc) do
    take_string(buf, ["\"" | acc])
  end

  defp take_string(<<c::utf8, buf::binary>>, acc)
       when c == 0x20
       when c == 0x21
       when c in 0x23..0x5B
       when c in 0x5D..0x7E do
    take_string(buf, [<<c::utf8>> | acc])
  end

  defp take_string(<<_, _::binary>> = all, _acc) do
    error(:invalid_string, all)
  end

  defp take_string(<<>>, _acc) do
    error(:expected_delimiter, <<>>)
  end

  defp parse_token(<<c, buf::binary>>) when is_ALPHA(c) when c == ?* do
    case take_token(buf, [c]) do
      {:ok, token, buf} -> {:ok, {:token, token}, buf}
      {:error, _} = err -> err
    end
  end

  defp parse_token(buf) do
    error(:invalid_token, buf)
  end

  defp take_token(<<c, buf::binary>>, acc) when is_tchar(c) when c in [?:, ?/] do
    take_token(buf, [c | acc])
  end

  defp take_token(buf, acc) do
    case buf do
      <<c, _::binary>> when is_EOE(c) -> {:ok, List.to_string(:lists.reverse(acc)), buf}
      <<>> -> {:ok, List.to_string(:lists.reverse(acc)), buf}
      _ -> error(:expected_delimiter, buf)
    end
  end

  defp take_ws_parameters(buf, acc) do
    case skip_ws(buf) do
      <<?;, buf::binary>> ->
        {p, buf} = take_parameter(skip_ws(buf))
        take_ws_parameters(buf, [p | acc])

      _buf_no_ws ->
        {dedup_keys(acc), buf}
    end
  end

  # On duplicate keys the last value wins, but the key keeps the position of
  # its first occurrence. The accumulator is given in reverse parsing order.
  defp dedup_keys([]) do
    []
  end

  defp dedup_keys(acc) do
    forward = :lists.reverse(acc)
    values = Map.new(forward)

    # Duplicate keys are rare, most of the time the list is already deduped.
    if map_size(values) == length(forward) do
      forward
    else
      {list, _} =
        Enum.flat_map_reduce(forward, values, fn
          {k, _}, values when is_map_key(values, k) ->
            {v, values} = Map.pop!(values, k)
            {[{k, v}], values}

          _, values ->
            {[], values}
        end)

      list
    end
  end

  defp take_parameter(buf) do
    case parse_key(buf) do
      {:ok, key, <<?=, buf::binary>>} ->
        {value, buf} = parse_bare_item(buf)
        {{key, value}, buf}

      {:bool_true, key, buf} ->
        {{key, {:boolean, true}}, buf}
    end
  end

  defp parse_key(<<c, buf::binary>>) when is_lcalpha(c) when c == ?* do
    take_key(buf, [c])
  end

  defp parse_key(buf) do
    fail(:invalid_key, buf)
  end

  defp take_key(<<c, buf::binary>>, acc)
       when is_lcalpha(c)
       when is_DIGIT(c)
       when c in [?_, ?-, ?., ?*] do
    take_key(buf, [c | acc])
  end

  defp take_key(<<?=, _::binary>> = buf, acc) do
    {:ok, List.to_string(:lists.reverse(acc)), buf}
  end

  defp take_key(buf, acc) do
    {:bool_true, List.to_string(:lists.reverse(acc)), buf}
  end

  defp skip_ws(buf)

  defp skip_ws(<<c, buf::binary>>) when is_OWS(c) do
    skip_ws(buf)
  end

  defp skip_ws(buf) do
    buf
  end

  defp error(errmsg, buf) do
    {:error, {errmsg, buf}}
  end

  @spec fail(atom, binary) :: no_return
  defp fail(errmsg, buf) do
    raise Error, reason: {errmsg, buf}
  end
end
