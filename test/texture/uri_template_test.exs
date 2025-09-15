defmodule Texture.UriTemplateTest do
  alias Texture.UriTemplate
  use ExUnit.Case, async: true

  describe "parsing to templates" do
    defp parse_template(source) do
      assert {:ok, parsed} = UriTemplate.parse(source)
      {:ok, parsed}
    end

    defp run_template(parsed, params) do
      UriTemplate.generate_uri(parsed, params)
    end

    test "simple variable expansion in path" do
      template = "/users/{id}"

      assert {:ok, parsed} = parse_template(template)

      assert "/users/42" = run_template(parsed, %{"id" => "42"})
      assert "/users/42" = run_template(parsed, %{id: "42"})
    end

    test "reserved expansion keeps reserved characters" do
      template = "/x/{+var}"

      assert {:ok, parsed} = parse_template(template)

      assert "/x/a/b?c=d&x=y" = run_template(parsed, %{"var" => "a/b?c=d&x=y"})
      assert "/x/a/b?c=d&x=y" = run_template(parsed, %{var: "a/b?c=d&x=y"})
    end

    test "simple expansion percent-encodes reserved characters" do
      template = "/x/{var}"

      assert {:ok, parsed} = parse_template(template)

      assert "/x/a%2Fb%3Fc%3Dd%26x%3Dy" = run_template(parsed, %{"var" => "a/b?c=d&x=y"})
      assert "/x/a%2Fb%3Fc%3Dd%26x%3Dy" = run_template(parsed, %{var: "a/b?c=d&x=y"})
    end

    test "fragment expansion" do
      template = "/p{#frag}"

      assert {:ok, parsed} = parse_template(template)

      assert "/p#x/y" = run_template(parsed, %{"frag" => "x/y"})
      assert "/p#x/y" = run_template(parsed, %{frag: "x/y"})
    end

    test "fragment expansion encodes non-reserved (unicode)" do
      template = "/p{#frag}"

      assert {:ok, parsed} = parse_template(template)

      assert "/p#caf%C3%A9" = run_template(parsed, %{"frag" => "café"})
      assert "/p#caf%C3%A9" = run_template(parsed, %{frag: "café"})
    end

    test "label operator" do
      template = "/d{.label}"

      assert {:ok, parsed} = parse_template(template)

      assert "/d.example" = run_template(parsed, %{"label" => "example"})
      assert "/d.example" = run_template(parsed, %{label: "example"})
    end

    test "label operator encodes spaces" do
      template = "/d{.label}"

      assert {:ok, parsed} = parse_template(template)

      assert "/d.has%20dots" = run_template(parsed, %{"label" => "has dots"})
      assert "/d.has%20dots" = run_template(parsed, %{label: "has dots"})
    end

    test "path segment expansion with explode list" do
      template = "/api{/segments*}"

      assert {:ok, parsed} = parse_template(template)

      assert "/api/v1/users/42" = run_template(parsed, %{"segments" => ["v1", "users", "42"]})
      assert "/api/v1/users/42" = run_template(parsed, %{segments: ["v1", "users", "42"]})
    end

    test "path segment expansion without explode encodes slashes" do
      template = "/files{/path}"

      assert {:ok, parsed} = parse_template(template)

      assert "/files/a%2Fb%2Fc" = run_template(parsed, %{"path" => "a/b/c"})
      assert "/files/a%2Fb%2Fc" = run_template(parsed, %{path: "a/b/c"})
    end

    test "reserved path expansion keeps slashes" do
      template = "/files{+path}"

      assert {:ok, parsed} = parse_template(template)

      assert "/files/a/b/c" = run_template(parsed, %{"path" => "/a/b/c"})
      assert "/files/a/b/c" = run_template(parsed, %{path: "/a/b/c"})
    end

    test "semicolon path-style parameter" do
      template = "/users{;id}"

      assert {:ok, parsed} = parse_template(template)

      assert "/users;id=42" = run_template(parsed, %{"id" => "42"})
      assert "/users;id=42" = run_template(parsed, %{id: "42"})
    end

    test "semicolon parameter with empty string" do
      template = "/users{;id}"

      assert {:ok, parsed} = parse_template(template)

      assert "/users;id" = run_template(parsed, %{"id" => ""})
      assert "/users;id" = run_template(parsed, %{id: ""})
    end

    test "semicolon parameter with exploded list" do
      template = "/m{;list*}"

      assert {:ok, parsed} = parse_template(template)

      assert "/m;list=a;list=b" = run_template(parsed, %{"list" => ["a", "b"]})
      assert "/m;list=a;list=b" = run_template(parsed, %{list: ["a", "b"]})
    end

    test "semicolon parameter with non-exploded list" do
      template = "/m{;list}"

      assert {:ok, parsed} = parse_template(template)

      assert "/m;list=a,b" = run_template(parsed, %{"list" => ["a", "b"]})
      assert "/m;list=a,b" = run_template(parsed, %{list: ["a", "b"]})
    end

    test "query form-style with single var" do
      template = "{?q}"

      assert {:ok, parsed} = parse_template(template)

      assert "?q=coffee" = run_template(parsed, %{"q" => "coffee"})
      assert "?q=coffee" = run_template(parsed, %{q: "coffee"})
    end

    test "query form-style with multiple vars and omission" do
      template = "{?x,y}"

      assert {:ok, parsed} = parse_template(template)

      assert "?x=1024&y=768" = run_template(parsed, %{"x" => "1024", "y" => "768"})
      assert "?x=1024" = run_template(parsed, %{"x" => "1024"})
    end

    test "query var with empty value is present" do
      template = "{?x}"

      assert {:ok, parsed} = parse_template(template)

      assert "?x=" = run_template(parsed, %{"x" => ""})
      assert "?x=" = run_template(parsed, %{x: ""})
    end

    test "query list non-exploded" do
      template = "{?list}"

      assert {:ok, parsed} = parse_template(template)

      assert "?list=red,green,blue" = run_template(parsed, %{"list" => ["red", "green", "blue"]})
      assert "?list=red,green,blue" = run_template(parsed, %{list: ["red", "green", "blue"]})
    end

    test "query list exploded" do
      template = "{?list*}"

      assert {:ok, parsed} = parse_template(template)

      assert "?list=red&list=green" = run_template(parsed, %{"list" => ["red", "green"]})
      assert "?list=red&list=green" = run_template(parsed, %{list: ["red", "green"]})
    end

    test "query continuation with &" do
      template = "?fixed=1{&x,y}"

      assert {:ok, parsed} = parse_template(template)

      assert "?fixed=1&x=2&y=3" = run_template(parsed, %{"x" => "2", "y" => "3"})
      assert "?fixed=1&x=2&y=3" = run_template(parsed, %{x: "2", y: "3"})
    end

    test "prefix modifier with simple expansion" do
      template = "/p/{var:3}"

      assert {:ok, parsed} = parse_template(template)

      assert "/p/abc" = run_template(parsed, %{"var" => "abcdef"})
      assert "/p/abc" = run_template(parsed, %{var: "abcdef"})
    end

    test "prefix modifier with reserved expansion" do
      template = "/base{+path:5}"

      assert {:ok, parsed} = parse_template(template)

      # NOTE: RFC 6570 prefix modifier keeps the trailing delimiter if it falls
      # within the prefix length. For source "/a/b/c" the first 5 characters are
      # "/a/b/", so the expected expansion includes the trailing slash.
      # See RFC 6570 Section 3.2.2 examples (e.g. {+path:5} -> "/foo/").
      assert "/base/a/b/" = run_template(parsed, %{"path" => "/a/b/c"})
      assert "/base/a/b/" = run_template(parsed, %{path: "/a/b/c"})
    end

    test "unicode encoding in simple expansion" do
      template = "/q/{term}"

      assert {:ok, parsed} = parse_template(template)

      assert "/q/caf%C3%A9" = run_template(parsed, %{"term" => "café"})
      assert "/q/caf%C3%A9" = run_template(parsed, %{term: "café"})
    end

    test "unicode percent-encoded in reserved expansion" do
      template = "/u/{+term}"

      assert {:ok, parsed} = parse_template(template)

      # RFC 6570 requires non-ASCII characters to be UTF-8 percent-encoded even
      # in reserved ('+') expansions. Only ASCII reserved characters like '/'
      # may remain unencoded. "東京/渋谷" becomes "%E6%9D%B1%E4%BA%AC/%E6%B8%8B%E8%B0%B7".
      assert "/u/%E6%9D%B1%E4%BA%AC/%E6%B8%8B%E8%B0%B7" =
               run_template(parsed, %{"term" => "東京/渋谷"})

      assert "/u/%E6%9D%B1%E4%BA%AC/%E6%B8%8B%E8%B0%B7" = run_template(parsed, %{term: "東京/渋谷"})
    end

    test "emoji percent-encoding in query" do
      template = "{?emoji}"

      assert {:ok, parsed} = parse_template(template)

      assert "?emoji=%F0%9F%99%82" = run_template(parsed, %{"emoji" => "🙂"})
      assert "?emoji=%F0%9F%99%82" = run_template(parsed, %{emoji: "🙂"})
    end

    test "undefined variable omits entire expression in path" do
      template = "/users{/id}"

      assert {:ok, parsed} = parse_template(template)

      assert "/users" = run_template(parsed, %{})
      assert "/users" = run_template(parsed, %{})
    end

    test "empty string in simple expansion contributes nothing between literals" do
      template = "/a{empty}b"

      assert {:ok, parsed} = parse_template(template)

      assert "/ab" = run_template(parsed, %{"empty" => ""})
      assert "/ab" = run_template(parsed, %{empty: ""})
    end

    test "mixed expressions and literals" do
      template = "https://ex.com{/ver}{/res*}{?q,lang}{&page}"

      assert {:ok, parsed} = parse_template(template)

      assert "https://ex.com/v1/users/42?q=caf%C3%A9&lang=fr&page=2" =
               run_template(parsed, %{
                 "ver" => "v1",
                 "res" => ["users", "42"],
                 "q" => "café",
                 "lang" => "fr",
                 "page" => "2"
               })

      assert "https://ex.com/v1/users/42?q=caf%C3%A9&lang=fr&page=2" =
               run_template(parsed, %{
                 ver: "v1",
                 res: ["users", "42"],
                 q: "café",
                 lang: "fr",
                 page: "2"
               })
    end

    test "numbers and booleans are coerced to strings" do
      template = "/t/{num}/{bool}"

      assert {:ok, parsed} = parse_template(template)

      assert "/t/0/false" = run_template(parsed, %{"num" => 0, "bool" => false})
      assert "/t/0/false" = run_template(parsed, %{num: 0, bool: false})
    end

    test "empty list omits query expression (non-exploded)" do
      template = "/s{?list}"

      assert {:ok, parsed} = parse_template(template)

      assert "/s" = run_template(parsed, %{"list" => []})
      assert "/s" = run_template(parsed, %{list: []})
    end

    test "empty list omits query expression (exploded)" do
      template = "/s{?list*}"

      assert {:ok, parsed} = parse_template(template)

      assert "/s" = run_template(parsed, %{"list" => []})
      assert "/s" = run_template(parsed, %{list: []})
    end

    test "empty map omits semicolon parameter block" do
      template = "/p{;map*}"

      assert {:ok, parsed} = parse_template(template)

      assert "/p" = run_template(parsed, %{"map" => %{}})
      assert "/p" = run_template(parsed, %{map: %{}})
    end

    test "fragment with prefix modifier and unicode" do
      template = "{#frag:6}"

      assert {:ok, parsed} = parse_template(template)

      assert "#caf%C3%A9-b" = run_template(parsed, %{"frag" => "café-bar"})
      assert "#caf%C3%A9-b" = run_template(parsed, %{frag: "café-bar"})
    end

    test "exploded map query has no guaranteed order" do
      template = "/m{?map*}"

      assert {:ok, parsed} = parse_template(template)

      result = run_template(parsed, %{"map" => %{"a" => "1", "b" => "2"}})
      assert result in ["/m?a=1&b=2", "/m?b=2&a=1"]

      result2 = run_template(parsed, %{map: %{"a" => "1", "b" => "2"}})
      assert result2 in ["/m?a=1&b=2", "/m?b=2&a=1"]
    end

    test "exploded map with mixed atom and binary keys" do
      template = "https://ex.com{?map*}"

      assert {:ok, parsed} = parse_template(template)

      result = run_template(parsed, %{"map" => %{:a => 1, "b" => 2}})
      assert result in ["https://ex.com?a=1&b=2", "https://ex.com?b=2&a=1"]

      result2 = run_template(parsed, %{map: %{"a" => 1, :b => 2}})
      assert result2 in ["https://ex.com?a=1&b=2", "https://ex.com?b=2&a=1"]
    end
  end
end
