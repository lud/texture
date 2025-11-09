defmodule Texture.UriTemplate.MatcherTest do
  alias Texture.UriTemplate
  alias Texture.UriTemplate.Matcher
  alias Texture.UriTemplate.TemplateMatchError
  use ExUnit.Case, async: true

  doctest Texture.UriTemplate, only: [match!: 2]

  # This test file contains everything that we care to support.

  defp match_template!(template, uri) do
    template
    |> UriTemplate.parse!()
    |> UriTemplate.match!(uri)
  end

  defp render!(template, values) do
    t = UriTemplate.parse!(template)
    UriTemplate.render(t, values)
  end

  describe "value parsing algorithm" do
    test "values are decoded" do
      assert {["Hello World!"], ""} = Matcher.take_multi("Hello%20World%21", param_sep: ?,, list_sep: nil)
    end

    test "parsing list as value" do
      opts = [param_sep: ?,, list_sep: nil]

      assert {["a", "b", "c"], ""} = Matcher.take_multi("a,b,c", opts)
      assert {["a", "b", "c"], "/"} = Matcher.take_multi("a,b,c/", opts)
    end

    test "param split on /, list split on ," do
      opts = [param_sep: ?/, list_sep: ?,]
      assert {[["a", "b", "c"], "d"], ""} = Matcher.take_multi("a,b,c/d", opts)
      assert {[["a", "b", "c"], "d"], "?"} = Matcher.take_multi("a,b,c/d?", opts)
    end
  end

  describe "default operator" do
    test "basic url parameters" do
      # with a single value for each parameter
      assert %{"foo" => "hello"} == match_template!("{foo}", "hello")
      assert %{"foo" => "hello", "bar" => "world"} == match_template!("{foo}/{bar}", "hello/world")
    end

    test "basic params with list" do
      template = "{foo}"
      values = %{"foo" => [1, 2, 3]}

      # with the default operator, lists are rendered with commas
      assert "1,2,3" = url = render!(template, values)

      # this can be matched on a single param
      assert %{"foo" => ["1", "2", "3"]} == match_template!(template, url)

      # we can match multiple parameters to a list or same length. Each parameter
      # gets a naked value.
      assert %{"foo" => "1", "bar" => "2"} == match_template!("{foo,bar}", "1,2")

      # it can also be matched on multiple parameters. In that case the last
      # parameter accumulates the extra items in a list value
      assert %{"foo" => "1", "bar" => ["2", "3"]} == match_template!("{foo,bar}", "1,2,3")

      # on the other side, if there are not enough values for the parameters, they
      # are assigned nil
      assert %{"foo" => "1", "bar" => nil, "baz" => nil} == match_template!("{foo,bar,baz}", "1")
      assert %{"foo" => "1", "bar" => "2", "baz" => nil} == match_template!("{foo,bar,baz}", "1,2")

      # if parameters are separated in different expressions, then the first
      # expression will take everything
      assert %{"foo" => ["1", "2"], "bar" => nil} == match_template!("{foo}{bar}", "1,2")
    end

    test "exploded map with default op" do
      template = "{foo*}"
      values = %{"foo" => %{a: 1, b: 2}}

      # an exploded map in default op is a list of keys
      assert "a=1,b=2" = url = render!(template, values)

      assert %{"foo" => %{"a" => "1", "b" => "2"}} == match_template!(template, url)
    end

    test "exploded map with default op, multiple params" do
      template = "{foo*,bar}"
      values = %{"foo" => %{a: 1, b: 2}, "bar" => 1}

      # an exploded map in default op is a list of keys
      assert "a=1,b=2,1" = url = render!(template, values)

      assert %{"foo" => %{"a" => "1", "b" => "2"}, "bar" => "1"} == match_template!(template, url)

      # foo is not exploded and should not take dictionary pairs
      assert %{"foo" => nil, "bar" => %{"a" => "1", "b" => "2", "c" => "3"}} ==
               match_template!("{foo,bar*}", "a=1,b=2,c=3")

      # both are exploded, foo will take everything
      assert %{"foo" => %{"a" => "1", "b" => "2", "c" => "3"}, "bar" => nil} ==
               match_template!("{foo*,bar*}", "a=1,b=2,c=3")

      # bar is exploded and will be set as a list
      assert %{"foo" => %{"a" => "1", "b" => "2"}, "bar" => ["x"], "stuff" => nil} ==
               match_template!("{foo*,bar*,stuff}", "a=1,b=2,x")
    end

    test "percent encoding edge cases" do
      # special characters that need percent encoding
      assert %{"foo" => "hello world"} == match_template!("{foo}", "hello%20world")
      assert %{"foo" => "hello+world"} == match_template!("{foo}", "hello%2Bworld")
      assert %{"foo" => "100%"} == match_template!("{foo}", "100%25")

      # reserved characters
      assert %{"foo" => "a:b"} == match_template!("{foo}", "a%3Ab")
      assert %{"foo" => "a/b"} == match_template!("{foo}", "a%2Fb")
      assert %{"foo" => "a?b"} == match_template!("{foo}", "a%3Fb")
      assert %{"foo" => "a#b"} == match_template!("{foo}", "a%23b")
      assert %{"foo" => "a[b]"} == match_template!("{foo}", "a%5Bb%5D")
      assert %{"foo" => "a@b"} == match_template!("{foo}", "a%40b")

      # percent encoding in lists
      assert %{"foo" => ["hello world", "foo bar"]} == match_template!("{foo}", "hello%20world,foo%20bar")

      # percent encoding in map keys and values
      assert %{"foo" => %{"hello world" => "foo bar"}} == match_template!("{foo*}", "hello%20world=foo%20bar")
    end

    test "empty and null values" do
      # empty value is nil
      assert %{"foo" => nil} == match_template!("{foo}", "")

      # empty in list context (commas with no values)
      assert %{"foo" => ["", "", ""]} == match_template!("{foo}", ",,")
      assert %{"foo" => ["a", "", "c"]} == match_template!("{foo}", "a,,c")

      # empty key or value in map
      assert %{"foo" => %{"" => "value"}} == match_template!("{foo*}", "=value")
      assert %{"foo" => %{"key" => ""}} == match_template!("{foo*}", "key=")
      assert %{"foo" => %{"" => ""}} == match_template!("{foo*}", "=")
    end

    test "unicode characters" do
      # unicode characters get percent encoded
      assert %{"foo" => "héllo"} == match_template!("{foo}", "h%C3%A9llo")
      assert %{"foo" => "日本語"} == match_template!("{foo}", "%E6%97%A5%E6%9C%AC%E8%AA%9E")
      assert %{"foo" => "emoji😀"} == match_template!("{foo}", "emoji%F0%9F%98%80")

      # unicode in lists
      assert %{"foo" => ["héllo", "wörld"]} == match_template!("{foo}", "h%C3%A9llo,w%C3%B6rld")

      # unicode in map keys and values
      assert %{"foo" => %{"clé" => "valeur"}} == match_template!("{foo*}", "cl%C3%A9=valeur")
    end

    test "special separator characters in values" do
      # comma in value needs encoding since comma is list separator
      assert %{"foo" => "a,b"} == match_template!("{foo}", "a%2Cb")

      # comma in list with encoding
      assert %{"foo" => ["a,b", "c"]} == match_template!("{foo}", "a%2Cb,c")

      # equals sign in non-map value
      assert %{"foo" => "a=b"} == match_template!("{foo}", "a%3Db")

      # equals in list
      assert %{"foo" => ["a=b", "c"]} == match_template!("{foo}", "a%3Db,c")
    end

    test "boundary conditions with long values" do
      # very long string
      long_string = String.duplicate("a", 1000)
      assert %{"foo" => long_string} == match_template!("{foo}", long_string)

      # many items in list
      values = Enum.map(1..100, &to_string/1)
      template = "{foo}"
      url = Enum.join(values, ",")
      assert %{"foo" => values} == match_template!(template, url)
    end

    test "extra values" do
      # simple value followed by list
      assert %{"foo" => "simple", "bar" => ["a", "b", "c"]} ==
               match_template!("{foo,bar}", "simple,a,b,c")

      # map followed by simple value
      assert %{"foo" => %{"a" => "1"}, "bar" => "simple"} ==
               match_template!("{foo*,bar}", "a=1,simple")
    end

    test "extra invalid values" do
      # simple value followed by key values but bar is not exploded
      assert_raise TemplateMatchError, ~r{unexpected dict}, fn ->
        match_template!("{foo,bar}", "simple,a=1,b=2")
      end

      # ok if bar is exploded
      assert %{"foo" => "simple", "bar" => %{"a" => "1", "b" => "2"}} = match_template!("{foo,bar*}", "simple,a=1,b=2")

      # map followed by simple value
      assert %{"foo" => %{"a" => "1"}, "bar" => "simple"} ==
               match_template!("{foo*,bar}", "a=1,simple")
    end

    test "duplicate parameter names behavior" do
      # when same parameter appears multiple times, the first occurence is
      # preserved. This is an implementation choice. The rationale is that path
      # parameters should not be overriden by query parameters, and our
      # algorithm does not consider the param source when merging, we simply
      # keep the first defined ones.
      assert %{"foo" => "first"} == match_template!("{foo}/{foo}", "first/second")
    end

    test "case sensitivity" do
      # parameter names are case sensitive
      assert %{"Foo" => "value"} == match_template!("{Foo}", "value")
      assert %{"foo" => "value1", "Foo" => "value2"} == match_template!("{foo}/{Foo}", "value1/value2")
    end

    test "numeric-like strings" do
      # numbers should be kept as strings
      assert %{"foo" => "123"} == match_template!("{foo}", "123")
      assert %{"foo" => "0"} == match_template!("{foo}", "0")
      assert %{"foo" => "3.14"} == match_template!("{foo}", "3.14")
      assert %{"foo" => "-42"} == match_template!("{foo}", "-42")
    end

    test "exploded list edge cases" do
      # single item in exploded list should return a list with one item
      assert %{"foo" => ["1"]} == match_template!("{foo*}", "1")

      # empty exploded list should get empty list or nil
      assert %{"foo" => nil} == match_template!("{foo*}", "")
    end

    test "map with numeric and special keys" do
      # numeric keys in maps
      assert %{"foo" => %{"123" => "value"}} == match_template!("{foo*}", "123=value")

      # special character keys (encoded)
      assert %{"foo" => %{"key-name" => "value"}} == match_template!("{foo*}", "key-name=value")
      assert %{"foo" => %{"key_name" => "value"}} == match_template!("{foo*}", "key_name=value")
      assert %{"foo" => %{"key.name" => "value"}} == match_template!("{foo*}", "key.name=value")
    end
  end

  describe "query parameters with ? " do
    test "query parameter" do
      template = "{?foo}"
      values = %{"foo" => [1, 2, 3]}

      # with the default operator, lists are rendered with commas
      assert "?foo=1,2,3" = url = render!(template, values)

      assert %{"foo" => ["1", "2", "3"]} == match_template!(template, url)
    end

    test "multiple query parameter" do
      template = "{?foo,bar}"
      values = %{"foo" => [1, 2, 3], "bar" => "hello"}

      # with the default operator, lists are rendered with commas
      assert "?foo=1,2,3&bar=hello" = url = render!(template, values)

      assert %{"foo" => ["1", "2", "3"], "bar" => "hello"} == match_template!(template, url)
    end

    test "exploded list query parameter" do
      template = "{?foo*,bar}"
      values = %{"foo" => [1, 2, 3], "bar" => "hello"}

      # with the default operator, lists are rendered with commas
      assert "?foo=1&foo=2&foo=3&bar=hello" = url = render!(template, values)

      assert %{"foo" => ["1", "2", "3"], "bar" => "hello"} == match_template!(template, url)
    end

    test "exploded map query parameter" do
      template = "{?foo*,bar*,baz}"
      values = %{"foo" => [1, 2, 3], "bar" => %{a: 1, b: 2}, "baz" => "astring"}

      # with the default operator, lists are rendered with commas
      assert "?foo=1&foo=2&foo=3&a=1&b=2&baz=astring" = url = render!(template, values)

      assert %{"foo" => ["1", "2", "3"], "baz" => "astring", "bar" => %{"a" => "1", "b" => "2"}} ==
               match_template!(template, url)
    end

    test "empty query parameter values" do
      # empty value with parameter name
      assert %{"foo" => nil} == match_template!("{?foo}", "?foo=")

      # multiple parameters, some empty
      assert %{"foo" => nil, "bar" => "value"} == match_template!("{?foo,bar}", "?foo=&bar=value")
      assert %{"foo" => "value", "bar" => nil} == match_template!("{?foo,bar}", "?foo=value&bar=")

      # empty in list
      assert %{"foo" => ["", "b", ""]} == match_template!("{?foo}", "?foo=,b,")
    end

    test "percent encoding in query parameters" do
      # spaces and special characters
      assert %{"foo" => "hello world"} == match_template!("{?foo}", "?foo=hello%20world")
      assert %{"foo" => "a+b"} == match_template!("{?foo}", "?foo=a%2Bb")
      assert %{"foo" => "100%"} == match_template!("{?foo}", "?foo=100%25")

      # reserved characters in query value
      assert %{"foo" => "a/b"} == match_template!("{?foo}", "?foo=a%2Fb")
      assert %{"foo" => "a?b"} == match_template!("{?foo}", "?foo=a%3Fb")
      assert %{"foo" => "a#b"} == match_template!("{?foo}", "?foo=a%23b")

      # ampersand needs encoding
      assert %{"foo" => "a&b"} == match_template!("{?foo}", "?foo=a%26b")

      # equals sign in value
      assert %{"foo" => "a=b"} == match_template!("{?foo}", "?foo=a%3Db")

      # percent encoding in parameter names of exploded map
      assert %{"foo" => %{"hello world" => "value"}} == match_template!("{?foo*}", "?hello%20world=value")
    end

    test "unicode in query parameters" do
      # unicode characters
      assert %{"foo" => "héllo"} == match_template!("{?foo}", "?foo=h%C3%A9llo")
      assert %{"foo" => "日本語"} == match_template!("{?foo}", "?foo=%E6%97%A5%E6%9C%AC%E8%AA%9E")
      assert %{"foo" => "emoji😀"} == match_template!("{?foo}", "?foo=emoji%F0%9F%98%80")

      # unicode in exploded map keys
      assert %{"foo" => %{"clé" => "valeur"}} == match_template!("{?foo*}", "?cl%C3%A9=valeur")
    end

    test "duplicate query parameter names" do
      # duplicate names in exploded list should accumulate
      assert %{"foo" => ["1", "2", "3"]} == match_template!("{?foo*}", "?foo=1&foo=2&foo=3")

      # mixed: explicit duplicate parameters in template
      assert %{"foo" => "last", "bar" => "value"} == match_template!("{?foo,bar,foo}", "?foo=first&bar=value&foo=last")
    end

    test "query parameter order preservation" do
      # parameters should maintain their order
      assert %{"foo" => "1", "bar" => "2", "baz" => "3"} ==
               match_template!("{?foo,bar,baz}", "?foo=1&bar=2&baz=3")

      # Query parameters are matched by name, not position, so order doesn't matter
      assert %{"foo" => "1", "bar" => "2", "baz" => "3"} ==
               match_template!("{?foo,bar,baz}", "?bar=2&foo=1&baz=3")
    end

    test "query with list containing special separators" do
      # comma in value (list separator) needs encoding
      assert %{"foo" => ["a,b", "c"]} == match_template!("{?foo}", "?foo=a%2Cb,c")

      # ampersand in value (param separator) needs encoding
      assert %{"foo" => "a&b"} == match_template!("{?foo}", "?foo=a%26b")
      assert %{"foo" => ["a&b", "c"]} == match_template!("{?foo}", "?foo=a%26b,c")
    end

    test "mixed exploded and non-exploded in query" do
      # non-exploded list followed by exploded list
      template = "{?foo,bar*}"

      assert %{"foo" => ["1", "2"], "bar" => ["3", "4"]} ==
               match_template!(template, "?foo=1,2&bar=3&bar=4")

      # exploded map followed by simple value
      template = "{?foo*,bar}"

      assert %{"foo" => %{"a" => "1", "b" => "2"}, "bar" => "value"} ==
               match_template!(template, "?a=1&b=2&bar=value")

      # complex mix
      template = "{?foo*,bar,baz*}"

      assert %{"foo" => ["1", "2"], "bar" => "value", "baz" => %{"x" => "10"}} ==
               match_template!(template, "?foo=1&foo=2&bar=value&x=10")
    end

    test "query parameter edge cases with maps" do
      # map with empty key
      assert %{"foo" => %{"" => "value"}} == match_template!("{?foo*}", "?=value")

      # map with empty value
      assert %{"foo" => %{"key" => ""}} == match_template!("{?foo*}", "?key=")

      # map with both empty
      assert %{"foo" => %{"" => ""}} == match_template!("{?foo*}", "?=")

      # map with numeric keys
      assert %{"foo" => %{"123" => "value"}} == match_template!("{?foo*}", "?123=value")
    end

    test "query without any parameters" do
      # just the ? prefix with no params should assign nil to the parameter
      assert %{"foo" => nil} == match_template!("{?foo}", "?")
    end

    test "handling malformed query strings" do
      # missing = in query pair - treats as name with empty value
      assert %{"foo" => nil} == match_template!("{?foo}", "?foo")

      # lists cannot be treated as keys though
      assert_raise TemplateMatchError, ~r{only key/values}, fn -> match_template!("{?foo}", "?foo,bar") end

      # using equal sing in the value is not supported
      assert_raise TemplateMatchError, ~r{invalid parameter syntax}, fn -> match_template!("{?foo}", "?foo==bar") end

      # trailing ampersand should be ignored
      assert %{"foo" => "value"} == match_template!("{?foo}", "?foo=value&")
    end

    test "long query values" do
      # very long query value
      long_value = String.duplicate("x", 1000)
      assert %{"foo" => long_value} == match_template!("{?foo}", "?foo=#{long_value}")

      # many query parameters
      template = "{?a,b,c,d,e,f,g,h,i,j}"

      assert %{
               "a" => "1",
               "b" => "2",
               "c" => "3",
               "d" => "4",
               "e" => "5",
               "f" => "6",
               "g" => "7",
               "h" => "8",
               "i" => "9",
               "j" => "10"
             } ==
               match_template!(template, "?a=1&b=2&c=3&d=4&e=5&f=6&g=7&h=8&i=9&j=10")
    end

    test "query parameter case sensitivity" do
      # parameter names are case sensitive
      assert %{"Foo" => "value"} == match_template!("{?Foo}", "?Foo=value")
      assert %{"foo" => "1", "Foo" => "2"} == match_template!("{?foo,Foo}", "?foo=1&Foo=2")
    end

    test "numeric-like query values" do
      # numbers should be kept as strings
      assert %{"foo" => "123"} == match_template!("{?foo}", "?foo=123")
      assert %{"foo" => "0"} == match_template!("{?foo}", "?foo=0")
      assert %{"foo" => "3.14"} == match_template!("{?foo}", "?foo=3.14")
      assert %{"foo" => "-42"} == match_template!("{?foo}", "?foo=-42")
    end

    test "query with special dot and dash characters" do
      # these are valid unencoded in query values
      assert %{"foo" => "value-with-dashes"} == match_template!("{?foo}", "?foo=value-with-dashes")
      assert %{"foo" => "value.with.dots"} == match_template!("{?foo}", "?foo=value.with.dots")
      assert %{"foo" => "value_with_underscores"} == match_template!("{?foo}", "?foo=value_with_underscores")
      assert %{"foo" => "value~with~tildes"} == match_template!("{?foo}", "?foo=value~with~tildes")
    end

    test "exploded list with single value" do
      # single value in exploded list
      assert %{"foo" => ["1"]} == match_template!("{?foo*}", "?foo=1")
    end

    test "complex nested exploded structures" do
      # exploded map within query, then another exploded list
      template = "{?map*,list*,simple}"

      assert %{"map" => %{"a" => "1", "b" => "2"}, "list" => ["x", "y"], "simple" => "value"} ==
               match_template!(template, "?a=1&b=2&list=x&list=y&simple=value")
    end

    test "all declared parameters present in result even when unmatched" do
      # All parameters in template should appear in result, even if they don't match anything
      template = "{?none,simple,items*,rest*,none_expl*}"

      assert %{
               "none" => nil,
               "simple" => "value",
               "items" => ["a", "b"],
               "rest" => %{"extra" => "1", "other" => "2"},
               "none_expl" => nil
             } == match_template!(template, "?extra=1&other=2&items=a&items=b&simple=value")

      # Test with different order and missing parameters
      template = "{?first,second*,third,fourth*}"

      assert %{
               "first" => "1",
               "second" => %{"x" => "10", "y" => "20"},
               "third" => nil,
               "fourth" => nil
             } == match_template!(template, "?first=1&x=10&y=20")

      # All exploded parameters without matches should be nil
      template = "{?all_exploded*,no_match*,another*}"

      assert %{
               "all_exploded" => nil,
               "no_match" => nil,
               "another" => nil
             } == match_template!(template, "?")
    end
  end

  describe "path segment parameters with /" do
    test "single path segment parameter" do
      template = "{/foo}"
      values = %{"foo" => "value"}

      # path segment adds leading slash
      assert "/value" = url = render!(template, values)
      assert %{"foo" => "value"} == match_template!(template, url)
    end

    test "multiple path segment parameters" do
      template = "{/foo,bar,baz}"
      values = %{"foo" => "one", "bar" => "two", "baz" => "three"}

      # each value gets its own slash prefix
      assert "/one/two/three" = url = render!(template, values)
      assert %{"foo" => "one", "bar" => "two", "baz" => "three"} == match_template!(template, url)
    end

    test "path segment with list (non-exploded)" do
      template = "{/foo}"
      values = %{"foo" => [1, 2, 3]}

      # non-exploded list uses comma separator
      assert "/1,2,3" = url = render!(template, values)
      assert %{"foo" => ["1", "2", "3"]} == match_template!(template, url)
    end

    test "path segment with exploded list" do
      template = "{/foo*}"
      values = %{"foo" => [1, 2, 3]}

      # exploded list gives each item its own slash prefix
      assert "/1/2/3" = url = render!(template, values)
      assert %{"foo" => ["1", "2", "3"]} == match_template!(template, url)
    end

    test "path segment with exploded map" do
      template = "{/foo*}"
      values = %{"foo" => %{a: 1, b: 2}}

      # exploded map renders as key=value pairs with slash separators
      assert "/a=1/b=2" = url = render!(template, values)
      assert %{"foo" => %{"a" => "1", "b" => "2"}} == match_template!(template, url)
    end

    test "mixed exploded and non-exploded path segments" do
      template = "{/foo,bar*}"
      values = %{"foo" => [1, 2], "bar" => [3, 4]}

      # foo is comma-separated, bar gets slash prefixes
      assert "/1,2/3/4" = url = render!(template, values)
      assert %{"foo" => ["1", "2"], "bar" => ["3", "4"]} == match_template!(template, url)
    end

    test "path segment with exploded map and other params" do
      template = "{/foo*,bar}"
      values = %{"foo" => %{a: 1, b: 2}, "bar" => "value"}

      assert "/a=1/b=2/value" = url = render!(template, values)
      assert %{"foo" => %{"a" => "1", "b" => "2"}, "bar" => "value"} == match_template!(template, url)
    end

    test "path segment with percent encoding" do
      # spaces need encoding
      template = "{/foo}"
      values = %{"foo" => "hello world"}
      assert "/hello%20world" = url = render!(template, values)
      assert %{"foo" => "hello world"} == match_template!(template, url)

      # special characters
      assert %{"foo" => "a/b"} == match_template!("{/foo}", "/a%2Fb")
      assert %{"foo" => "a?b"} == match_template!("{/foo}", "/a%3Fb")
      assert %{"foo" => "a#b"} == match_template!("{/foo}", "/a%23b")

      # percent encoding in lists
      template = "{/foo}"
      values = %{"foo" => ["hello world", "foo bar"]}
      assert "/hello%20world,foo%20bar" = url = render!(template, values)
      assert %{"foo" => ["hello world", "foo bar"]} == match_template!(template, url)
    end

    test "path segment with unicode" do
      template = "{/foo}"
      values = %{"foo" => "héllo"}
      assert "/h%C3%A9llo" = url = render!(template, values)
      assert %{"foo" => "héllo"} == match_template!(template, url)

      values = %{"foo" => "日本語"}
      assert "/%E6%97%A5%E6%9C%AC%E8%AA%9E" = url = render!(template, values)
      assert %{"foo" => "日本語"} == match_template!(template, url)

      values = %{"foo" => ["héllo", "wörld"]}
      assert "/h%C3%A9llo,w%C3%B6rld" = url = render!(template, values)
      assert %{"foo" => ["héllo", "wörld"]} == match_template!(template, url)

      # exploded list with unicode
      template = "{/foo*}"
      assert "/h%C3%A9llo/w%C3%B6rld" = url = render!(template, values)
      assert %{"foo" => ["héllo", "wörld"]} == match_template!(template, url)
    end

    test "path segment with empty values" do
      # empty value
      template = "{/foo}"
      values = %{"foo" => ""}
      assert "/" = url = render!(template, values)
      assert %{"foo" => nil} == match_template!(template, url)

      # multiple params with some empty
      template = "{/foo,bar}"
      values = %{"foo" => "", "bar" => "value"}
      assert "//value" = url = render!(template, values)
      assert %{"foo" => nil, "bar" => "value"} == match_template!(template, url)

      values = %{"foo" => "value", "bar" => ""}
      assert "/value/" = url = render!(template, values)
      assert %{"foo" => "value", "bar" => nil} == match_template!(template, url)

      # empty in list
      template = "{/foo}"
      values = %{"foo" => ["", "b", ""]}
      assert "/,b," = url = render!(template, values)
      assert %{"foo" => ["", "b", ""]} == match_template!(template, url)
    end

    test "path segment exploded list with empty values" do
      # empty values in exploded list
      template = "{/foo*}"
      values = %{"foo" => ["", "b", ""]}
      assert "//b/" = url = render!(template, values)
      assert %{"foo" => ["", "b", ""]} == match_template!(template, url)
    end

    test "path segment with comma in value" do
      # comma needs encoding in non-exploded (since comma is list separator)
      template = "{/foo}"
      values = %{"foo" => "a,b"}
      assert "/a%2Cb" = url = render!(template, values)
      assert %{"foo" => "a,b"} == match_template!(template, url)

      # comma in exploded list item
      template = "{/foo*}"
      values = %{"foo" => ["a,b", "c"]}
      assert "/a%2Cb/c" = url = render!(template, values)
      assert %{"foo" => ["a,b", "c"]} == match_template!(template, url)
    end

    test "path segment with equals in value" do
      # equals doesn't need encoding in simple value
      template = "{/foo}"
      values = %{"foo" => "a=b"}
      assert "/a%3Db" = url = render!(template, values)
      assert %{"foo" => "a=b"} == match_template!(template, url)

      # equals in non-exploded list
      values = %{"foo" => ["a=b", "c"]}
      assert "/a%3Db,c" = url = render!(template, values)
      assert %{"foo" => ["a=b", "c"]} == match_template!(template, url)
    end

    test "path segment with map containing special characters" do
      # special chars in map keys and values
      template = "{/foo*}"
      values = %{"foo" => %{"hello world" => "foo bar"}}
      assert "/hello%20world=foo%20bar" = url = render!(template, values)
      assert %{"foo" => %{"hello world" => "foo bar"}} == match_template!(template, url)

      values = %{"foo" => %{"key/name" => "value"}}
      assert "/key%2Fname=value" = url = render!(template, values)
      assert %{"foo" => %{"key/name" => "value"}} == match_template!(template, url)
    end

    test "path segment with multiple params accumulating values" do
      # first param takes single value, second takes rest as list
      template = "{/foo,bar}"
      values = %{"foo" => "1", "bar" => ["2", "3"]}
      assert "/1/2,3" = url = render!(template, values)
      assert %{"foo" => "1", "bar" => ["2", "3"]} == match_template!(template, url)

      # with more params
      template = "{/foo,bar,baz}"
      values = %{"foo" => "1", "bar" => "2", "baz" => ["3", "4", "5"]}
      assert "/1/2/3,4,5" = url = render!(template, values)
      assert %{"foo" => "1", "bar" => "2", "baz" => ["3", "4", "5"]} == match_template!(template, url)
    end

    test "path segment with insufficient values" do
      # not enough values for all params
      template = "{/foo,bar}"
      values = %{"foo" => "1"}
      assert "/1" = url = render!(template, values)
      assert %{"foo" => "1", "bar" => nil} == match_template!(template, url)

      template = "{/foo,bar,baz}"
      values = %{"foo" => "1"}
      assert "/1" = url = render!(template, values)
      assert %{"foo" => "1", "bar" => nil, "baz" => nil} == match_template!(template, url)
    end

    test "path segment exploded map accumulates all" do
      # exploded map as first param takes all key=value pairs
      template = "{/foo*,bar}"
      values = %{"foo" => %{a: 1, b: 2, c: 3}}
      assert "/a=1/b=2/c=3" = url = render!(template, values)
      assert %{"foo" => %{"a" => "1", "b" => "2", "c" => "3"}, "bar" => nil} == match_template!(template, url)

      # exploded map with following simple value
      values = %{"foo" => %{a: 1, b: 2}, "bar" => "value"}
      assert "/a=1/b=2/value" = url = render!(template, values)
      assert %{"foo" => %{"a" => "1", "b" => "2"}, "bar" => "value"} == match_template!(template, url)
    end

    test "path segment non-exploded map" do
      template = "{/foo}"
      values = %{"foo" => %{a: 1, b: 2}}

      # non-exploded map uses comma separator: key,value,key,value (no equals signs)
      # Per RFC 6570: {/keys} with keys={"semi":";","dot":".","comma":","} => /semi,%3B,dot,.,comma,%2C
      assert "/a,1,b,2" = url = render!(template, values)

      # When matching, this is ambiguous and will be parsed as a list, not a map
      # There's no way to distinguish ["a", "1", "b", "2"] from %{"a" => "1", "b" => "2"}
      # in the format "a,1,b,2" without equals signs
      assert %{"foo" => ["a", "1", "b", "2"]} == match_template!(template, url)
    end

    test "path segment with long values" do
      # very long path segment
      long_value = String.duplicate("x", 1000)
      template = "{/foo}"
      url = render!(template, %{"foo" => long_value})
      assert "/#{long_value}" == url
      assert %{"foo" => long_value} == match_template!(template, url)

      # many values in exploded list
      values_list = Enum.map(1..100, &to_string/1)
      template = "{/foo*}"
      url_from_render = render!(template, %{"foo" => values_list})
      url_expected = "/" <> Enum.join(values_list, "/")
      assert url_from_render == url_expected
      assert %{"foo" => values_list} == match_template!(template, url_from_render)
    end

    test "path segment case sensitivity" do
      template = "{/Foo}"
      values = %{"Foo" => "value"}
      assert "/value" = url = render!(template, values)
      assert %{"Foo" => "value"} == match_template!(template, url)

      template = "{/foo,Foo}"
      values = %{"foo" => "value1", "Foo" => "value2"}
      assert "/value1/value2" = url = render!(template, values)
      assert %{"foo" => "value1", "Foo" => "value2"} == match_template!(template, url)
    end

    test "path segment numeric-like strings" do
      template = "{/foo}"
      assert "/123" = url = render!(template, %{"foo" => "123"})
      assert %{"foo" => "123"} == match_template!(template, url)

      assert "/0" = url = render!(template, %{"foo" => "0"})
      assert %{"foo" => "0"} == match_template!(template, url)

      assert "/3.14" = url = render!(template, %{"foo" => "3.14"})
      assert %{"foo" => "3.14"} == match_template!(template, url)

      assert "/-42" = url = render!(template, %{"foo" => "-42"})
      assert %{"foo" => "-42"} == match_template!(template, url)
    end

    test "path segment with map having numeric keys" do
      template = "{/foo*}"
      values = %{"foo" => %{"123" => "value"}}
      assert "/123=value" = url = render!(template, values)
      assert %{"foo" => %{"123" => "value"}} == match_template!(template, url)
    end

    test "combining path segments with other operators" do
      # path segment followed by query
      template = "/api{/version,resource}{?id}"
      values = %{"version" => "v1", "resource" => "users", "id" => "42"}
      assert "/api/v1/users?id=42" = url = render!(template, values)
      assert %{"version" => "v1", "resource" => "users", "id" => "42"} == match_template!(template, url)

      # default operator followed by path segment
      template = "/api/{version}{/resource}"
      values = %{"version" => "v1", "resource" => "users"}
      assert "/api/v1/users" = url = render!(template, values)
      assert %{"version" => "v1", "resource" => "users"} == match_template!(template, url)
    end

    test "path segment exploded list vs non-exploded in same expression" do
      template = "{/foo*,bar,baz*}"
      values = %{"foo" => [1, 2], "bar" => [3, 4], "baz" => [5, 6]}

      # foo exploded, bar comma-separated, baz exploded
      assert "/1/2/3,4/5/6" = url = render!(template, values)
      assert %{"foo" => ["1", "2"], "bar" => ["3", "4"], "baz" => ["5", "6"]} == match_template!(template, url)
    end

    test "path segment with map followed by list" do
      template = "{/map*,list*}"
      values = %{"map" => %{a: 1, b: 2}, "list" => [3, 4]}

      assert "/a=1/b=2/3/4" = url = render!(template, values)
      assert %{"map" => %{"a" => "1", "b" => "2"}, "list" => ["3", "4"]} == match_template!(template, url)
    end

    test "path segment error cases" do
      # non-exploded param receiving dict values is skipped, so both foo and bar
      # are skipped, and we get an error about extra parameters
      assert_raise TemplateMatchError, ~r{extra values}, fn ->
        match_template!("{/foo,bar}", "/a=1/b=2/c=3")
      end

      # but works if exploded
      template = "{/foo*,bar}"
      values = %{"foo" => %{a: 1, b: 2, c: 3}}
      assert "/a=1/b=2/c=3" = url = render!(template, values)
      assert %{"foo" => %{"a" => "1", "b" => "2", "c" => "3"}, "bar" => nil} == match_template!(template, url)
    end

    test "path segment with trailing slash handling" do
      # extra trailing slash should not match if not expected
      template = "{/foo}"
      values = %{"foo" => "value"}
      assert "/value" = url = render!(template, values)
      assert %{"foo" => "value"} == match_template!(template, url)

      # If the template has literal text after, the slash matters
      template = "{/foo}/"
      assert "/value/" = url = render!(template, values)
      assert %{"foo" => "value"} == match_template!(template, url)
    end
  end
end
