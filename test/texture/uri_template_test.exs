defmodule Texture.UriTemplateTest do
  alias Texture.UriTemplate
  use ExUnit.Case, async: true

  doctest UriTemplate

  @rfc_sample_data %{
    "count" => ["one", "two", "three"],
    "dom" => ["example", "com"],
    "dub" => "me/too",
    "hello" => "Hello World!",
    "half" => "50%",
    "var" => "value",
    "who" => "fred",
    "base" => "http://example.com/home/",
    "path" => "/foo/bar",
    "list" => ["red", "green", "blue"],
    # It works for maps but the order is not preserved, so we can use a keyword
    # "keys" => %{"semi" => ";", "dot" => ".", "comma" => ","},
    "keys" => [semi: ";", dot: ".", comma: ","],
    "v" => "6",
    "x" => "1024",
    "y" => "768",
    "empty" => "",
    "empty_keys" => %{},
    # "undef" => ___,
    "year" => ["1965", "2000", "2012"],
    "semi" => ";"
  }

  defp parse_template(source) do
    assert {:ok, parsed} = UriTemplate.parse(source)
    {:ok, parsed}
  end

  defp render(parsed, params) do
    UriTemplate.render(parsed, params)
  end

  defp rfc_example(tpl) do
    {:ok, parsed} = parse_template(tpl)
    render(parsed, @rfc_sample_data)
  end

  describe "RFC6570 Examples 3.2.1 Variable Expansion - Basic Lists" do
    test "list expansion examples" do
      assert "one,two,three" = rfc_example("{count}")
      assert "one,two,three" = rfc_example("{count*}")
      assert "/one,two,three" = rfc_example("{/count}")
      assert "/one/two/three" = rfc_example("{/count*}")
      assert ";count=one,two,three" = rfc_example("{;count}")
      assert ";count=one;count=two;count=three" = rfc_example("{;count*}")
      assert "?count=one,two,three" = rfc_example("{?count}")
      assert "?count=one&count=two&count=three" = rfc_example("{?count*}")
      assert "&count=one&count=two&count=three" = rfc_example("{&count*}")
    end
  end

  describe "RFC6570 Examples 3.2.2 Simple String Expansion" do
    test "simple string expansion" do
      assert "value" = rfc_example("{var}")
      assert "Hello%20World%21" = rfc_example("{hello}")
      assert "50%25" = rfc_example("{half}")
      assert "OX" = rfc_example("O{empty}X")
      assert "OX" = rfc_example("O{undef}X")
      assert "1024,768" = rfc_example("{x,y}")
      assert "1024,Hello%20World%21,768" = rfc_example("{x,hello,y}")
      assert "?1024," = rfc_example("?{x,empty}")
      assert "?1024" = rfc_example("?{x,undef}")
      assert "?768" = rfc_example("?{undef,y}")
      assert "val" = rfc_example("{var:3}")
      assert "value" = rfc_example("{var:30}")
      assert "red,green,blue" = rfc_example("{list}")
      assert "red,green,blue" = rfc_example("{list*}")
      assert "semi,%3B,dot,.,comma,%2C" = rfc_example("{keys}")
      assert "semi=%3B,dot=.,comma=%2C" = rfc_example("{keys*}")
    end
  end

  describe "RFC6570 Examples 3.2.3 Reserved Expansion" do
    test "reserved expansion" do
      assert "value" = rfc_example("{+var}")
      assert "Hello%20World!" = rfc_example("{+hello}")
      assert "50%25" = rfc_example("{+half}")
      assert "http%3A%2F%2Fexample.com%2Fhome%2Findex" = rfc_example("{base}index")
      assert "http://example.com/home/index" = rfc_example("{+base}index")
      assert "OX" = rfc_example("O{+empty}X")
      assert "OX" = rfc_example("O{+undef}X")
      assert "/foo/bar/here" = rfc_example("{+path}/here")
      assert "here?ref=/foo/bar" = rfc_example("here?ref={+path}")
      assert "up/foo/barvalue/here" = rfc_example("up{+path}{var}/here")
      assert "1024,Hello%20World!,768" = rfc_example("{+x,hello,y}")
      assert "/foo/bar,1024/here" = rfc_example("{+path,x}/here")
      assert "/foo/b/here" = rfc_example("{+path:6}/here")
      assert "red,green,blue" = rfc_example("{+list}")
      assert "red,green,blue" = rfc_example("{+list*}")
      assert "semi,;,dot,.,comma,," = rfc_example("{+keys}")
      assert "semi=;,dot=.,comma=," = rfc_example("{+keys*}")
    end
  end

  describe "RFC6570 Examples 3.2.4 Fragment Expansion" do
    test "fragment expansion" do
      assert "#value" = rfc_example("{#var}")
      assert "#Hello%20World!" = rfc_example("{#hello}")
      assert "#50%25" = rfc_example("{#half}")
      assert "foo#" = rfc_example("foo{#empty}")
      assert "foo" = rfc_example("foo{#undef}")
      assert "#1024,Hello%20World!,768" = rfc_example("{#x,hello,y}")
      assert "#/foo/bar,1024/here" = rfc_example("{#path,x}/here")
      assert "#/foo/b/here" = rfc_example("{#path:6}/here")
      assert "#red,green,blue" = rfc_example("{#list}")
      assert "#red,green,blue" = rfc_example("{#list*}")
      assert "#semi,;,dot,.,comma,," = rfc_example("{#keys}")
      assert "#semi=;,dot=.,comma=," = rfc_example("{#keys*}")
    end
  end

  describe "RFC6570 Examples 3.2.5 Label Expansion with Dot-Prefix" do
    test "label expansion" do
      assert ".fred" = rfc_example("{.who}")
      assert ".fred.fred" = rfc_example("{.who,who}")
      assert ".50%25.fred" = rfc_example("{.half,who}")
      assert "www.example.com" = rfc_example("www{.dom*}")
      assert "X.value" = rfc_example("X{.var}")
      assert "X." = rfc_example("X{.empty}")
      assert "X" = rfc_example("X{.undef}")
      assert "X.val" = rfc_example("X{.var:3}")
      assert "X.red,green,blue" = rfc_example("X{.list}")
      assert "X.red.green.blue" = rfc_example("X{.list*}")
      assert "X.semi,%3B,dot,.,comma,%2C" = rfc_example("X{.keys}")
      assert "X.semi=%3B.dot=..comma=%2C" = rfc_example("X{.keys*}")
      assert "X" = rfc_example("X{.empty_keys}")
      assert "X" = rfc_example("X{.empty_keys*}")
    end
  end

  describe "RFC6570 Examples 3.2.6 Path Segment Expansion" do
    test "path segment expansion" do
      assert "/fred" = rfc_example("{/who}")
      assert "/fred/fred" = rfc_example("{/who,who}")
      assert "/50%25/fred" = rfc_example("{/half,who}")
      assert "/fred/me%2Ftoo" = rfc_example("{/who,dub}")
      assert "/value" = rfc_example("{/var}")
      assert "/value/" = rfc_example("{/var,empty}")
      assert "/value" = rfc_example("{/var,undef}")
      assert "/value/1024/here" = rfc_example("{/var,x}/here")
      assert "/v/value" = rfc_example("{/var:1,var}")
      assert "/red,green,blue" = rfc_example("{/list}")
      assert "/red/green/blue" = rfc_example("{/list*}")
      assert "/red/green/blue/%2Ffoo" = rfc_example("{/list*,path:4}")
      assert "/semi,%3B,dot,.,comma,%2C" = rfc_example("{/keys}")
      assert "/semi=%3B/dot=./comma=%2C" = rfc_example("{/keys*}")
    end
  end

  describe "RFC6570 Examples 3.2.7 Path-Style Parameter Expansion" do
    test "path-style parameter expansion" do
      assert ";who=fred" = rfc_example("{;who}")
      assert ";half=50%25" = rfc_example("{;half}")
      assert ";empty" = rfc_example("{;empty}")
      assert ";v=6;empty;who=fred" = rfc_example("{;v,empty,who}")
      assert ";v=6;who=fred" = rfc_example("{;v,bar,who}")
      assert ";x=1024;y=768" = rfc_example("{;x,y}")
      assert ";x=1024;y=768;empty" = rfc_example("{;x,y,empty}")
      assert ";x=1024;y=768" = rfc_example("{;x,y,undef}")
      assert ";hello=Hello" = rfc_example("{;hello:5}")
      assert ";list=red,green,blue" = rfc_example("{;list}")
      assert ";list=red;list=green;list=blue" = rfc_example("{;list*}")
      assert ";keys=semi,%3B,dot,.,comma,%2C" = rfc_example("{;keys}")
      assert ";semi=%3B;dot=.;comma=%2C" = rfc_example("{;keys*}")
    end
  end

  describe "RFC6570 Examples 3.2.8 Form-Style Query Expansion" do
    test "form-style query expansion" do
      assert "?who=fred" = rfc_example("{?who}")
      assert "?half=50%25" = rfc_example("{?half}")
      assert "?x=1024&y=768" = rfc_example("{?x,y}")
      assert "?x=1024&y=768&empty=" = rfc_example("{?x,y,empty}")
      assert "?x=1024&y=768" = rfc_example("{?x,y,undef}")
      assert "?var=val" = rfc_example("{?var:3}")
      assert "?list=red,green,blue" = rfc_example("{?list}")
      assert "?list=red&list=green&list=blue" = rfc_example("{?list*}")
      assert "?keys=semi,%3B,dot,.,comma,%2C" = rfc_example("{?keys}")
      assert "?semi=%3B&dot=.&comma=%2C" = rfc_example("{?keys*}")
    end
  end

  describe "RFC6570 Examples 3.2.9 Form-Style Query Continuation" do
    test "form-style query continuation" do
      assert "&who=fred" = rfc_example("{&who}")
      assert "&half=50%25" = rfc_example("{&half}")
      assert "?fixed=yes&x=1024" = rfc_example("?fixed=yes{&x}")
      assert "&x=1024&y=768&empty=" = rfc_example("{&x,y,empty}")
      assert "&x=1024&y=768" = rfc_example("{&x,y,undef}")
      assert "&var=val" = rfc_example("{&var:3}")
      assert "&list=red,green,blue" = rfc_example("{&list}")
      assert "&list=red&list=green&list=blue" = rfc_example("{&list*}")
      assert "&keys=semi,%3B,dot,.,comma,%2C" = rfc_example("{&keys}")
      assert "&semi=%3B&dot=.&comma=%2C" = rfc_example("{&keys*}")
    end
  end

  describe "RFC6570 Examples 2.4.1 Prefix Values" do
    test "prefix modifier examples" do
      assert "value" = rfc_example("{var}")
      assert "value" = rfc_example("{var:20}")
      assert "val" = rfc_example("{var:3}")
      assert "%3B" = rfc_example("{semi}")
      assert "%3B" = rfc_example("{semi:2}")
    end
  end

  describe "RFC6570 Examples 2.4.2 Composite Values - Explode" do
    test "explode modifier examples" do
      assert "find?year=1965&year=2000&year=2012" = rfc_example("find{?year*}")
      assert "www.example.com" = rfc_example("www{.dom*}")
    end
  end

  describe "RFC6570 Examples Level 1 Examples" do
    test "simple string expansion" do
      assert "value" = rfc_example("{var}")
      assert "Hello%20World%21" = rfc_example("{hello}")
    end
  end

  describe "RFC6570 Examples Level 2 Examples" do
    test "reserved string expansion" do
      assert "value" = rfc_example("{+var}")
      assert "Hello%20World!" = rfc_example("{+hello}")
      assert "/foo/bar/here" = rfc_example("{+path}/here")
      assert "here?ref=/foo/bar" = rfc_example("here?ref={+path}")
    end

    test "fragment expansion" do
      assert "X#value" = rfc_example("X{#var}")
      assert "X#Hello%20World!" = rfc_example("X{#hello}")
    end
  end

  describe "RFC6570 Examples Level 3 Examples" do
    test "string expansion with multiple variables" do
      assert "map?1024,768" = rfc_example("map?{x,y}")
      assert "1024,Hello%20World%21,768" = rfc_example("{x,hello,y}")
    end

    test "reserved expansion with multiple variables" do
      assert "1024,Hello%20World!,768" = rfc_example("{+x,hello,y}")
      assert "/foo/bar,1024/here" = rfc_example("{+path,x}/here")
    end

    test "fragment expansion with multiple variables" do
      assert "#1024,Hello%20World!,768" = rfc_example("{#x,hello,y}")
      assert "#/foo/bar,1024/here" = rfc_example("{#path,x}/here")
    end

    test "label expansion" do
      assert "X.value" = rfc_example("X{.var}")
      assert "X.1024.768" = rfc_example("X{.x,y}")
    end

    test "path segments" do
      assert "/value" = rfc_example("{/var}")
      assert "/value/1024/here" = rfc_example("{/var,x}/here")
    end

    test "path-style parameters" do
      assert ";x=1024;y=768" = rfc_example("{;x,y}")
      assert ";x=1024;y=768;empty" = rfc_example("{;x,y,empty}")
    end

    test "form-style query" do
      assert "?x=1024&y=768" = rfc_example("{?x,y}")
      assert "?x=1024&y=768&empty=" = rfc_example("{?x,y,empty}")
    end

    test "form-style query continuation" do
      assert "?fixed=yes&x=1024" = rfc_example("?fixed=yes{&x}")
      assert "&x=1024&y=768&empty=" = rfc_example("{&x,y,empty}")
    end
  end

  describe "RFC6570 Examples Level 4 Examples" do
    test "string expansion with value modifiers" do
      assert "val" = rfc_example("{var:3}")
      assert "value" = rfc_example("{var:30}")
      assert "red,green,blue" = rfc_example("{list}")
      assert "red,green,blue" = rfc_example("{list*}")
      assert "semi,%3B,dot,.,comma,%2C" = rfc_example("{keys}")
      assert "semi=%3B,dot=.,comma=%2C" = rfc_example("{keys*}")
    end

    test "reserved expansion with value modifiers" do
      assert "/foo/b/here" = rfc_example("{+path:6}/here")
      assert "red,green,blue" = rfc_example("{+list}")
      assert "red,green,blue" = rfc_example("{+list*}")
      assert "semi,;,dot,.,comma,," = rfc_example("{+keys}")
      assert "semi=;,dot=.,comma=," = rfc_example("{+keys*}")
    end

    test "fragment expansion with value modifiers" do
      assert "#/foo/b/here" = rfc_example("{#path:6}/here")
      assert "#red,green,blue" = rfc_example("{#list}")
      assert "#red,green,blue" = rfc_example("{#list*}")
      assert "#semi,;,dot,.,comma,," = rfc_example("{#keys}")
      assert "#semi=;,dot=.,comma=," = rfc_example("{#keys*}")
    end

    test "label expansion with value modifiers" do
      assert "X.val" = rfc_example("X{.var:3}")
      assert "X.red,green,blue" = rfc_example("X{.list}")
      assert "X.red.green.blue" = rfc_example("X{.list*}")
      assert "X.semi,%3B,dot,.,comma,%2C" = rfc_example("X{.keys}")
      assert "X.semi=%3B.dot=..comma=%2C" = rfc_example("X{.keys*}")
    end

    test "path segments with value modifiers" do
      assert "/v/value" = rfc_example("{/var:1,var}")
      assert "/red,green,blue" = rfc_example("{/list}")
      assert "/red/green/blue" = rfc_example("{/list*}")
      assert "/red/green/blue/%2Ffoo" = rfc_example("{/list*,path:4}")
      assert "/semi,%3B,dot,.,comma,%2C" = rfc_example("{/keys}")
      assert "/semi=%3B/dot=./comma=%2C" = rfc_example("{/keys*}")
    end

    test "path-style parameters with value modifiers" do
      assert ";hello=Hello" = rfc_example("{;hello:5}")
      assert ";list=red,green,blue" = rfc_example("{;list}")
      assert ";list=red;list=green;list=blue" = rfc_example("{;list*}")
      assert ";keys=semi,%3B,dot,.,comma,%2C" = rfc_example("{;keys}")
      assert ";semi=%3B;dot=.;comma=%2C" = rfc_example("{;keys*}")
    end

    test "form-style query with value modifiers" do
      assert "?var=val" = rfc_example("{?var:3}")
      assert "?list=red,green,blue" = rfc_example("{?list}")
      assert "?list=red&list=green&list=blue" = rfc_example("{?list*}")
      assert "?keys=semi,%3B,dot,.,comma,%2C" = rfc_example("{?keys}")
      assert "?semi=%3B&dot=.&comma=%2C" = rfc_example("{?keys*}")
    end

    test "form-style query continuation with value modifiers" do
      assert "&var=val" = rfc_example("{&var:3}")
      assert "&list=red,green,blue" = rfc_example("{&list}")
      assert "&list=red&list=green&list=blue" = rfc_example("{&list*}")
      assert "&keys=semi,%3B,dot,.,comma,%2C" = rfc_example("{&keys}")
      assert "&semi=%3B&dot=.&comma=%2C" = rfc_example("{&keys*}")
    end
  end

  describe "parsing to templates" do
    test "simple variable expansion in path" do
      template = "/users/{id}"

      assert {:ok, parsed} = parse_template(template)

      assert "/users/42" = render(parsed, %{"id" => "42"})
      assert "/users/42" = render(parsed, %{id: "42"})
    end

    test "unicode characters" do
      assert {:ok, parsed} = parse_template("/héé{/x,y}")
      assert "/héé/1/2" = render(parsed, %{x: 1, y: 2})
    end

    test "iprivate characters" do
      assert {:ok, parsed} = parse_template("/h\u{10FFFD}\u{10FFFD}{/x,y}")
      assert "/h\u{10FFFD}\u{10FFFD}/1/2" = render(parsed, %{x: 1, y: 2})
    end

    test "percent encoded characters" do
      assert {:ok, parsed} = parse_template("/h%20%20{/x,y}")
      assert "/h%20%20/1/2" = render(parsed, %{x: 1, y: 2})
    end

    test "reserved expansion keeps reserved characters" do
      template = "/x/{+var}"

      assert {:ok, parsed} = parse_template(template)

      assert "/x/a/b?c=d&x=y" = render(parsed, %{"var" => "a/b?c=d&x=y"})
      assert "/x/a/b?c=d&x=y" = render(parsed, %{var: "a/b?c=d&x=y"})
    end

    test "simple expansion percent-encodes reserved characters" do
      template = "/x/{var}"

      assert {:ok, parsed} = parse_template(template)

      assert "/x/a%2Fb%3Fc%3Dd%26x%3Dy" = render(parsed, %{"var" => "a/b?c=d&x=y"})
      assert "/x/a%2Fb%3Fc%3Dd%26x%3Dy" = render(parsed, %{var: "a/b?c=d&x=y"})
    end

    test "fragment expansion" do
      template = "/p{#frag}"

      assert {:ok, parsed} = parse_template(template)

      assert "/p#x/y" = render(parsed, %{"frag" => "x/y"})
      assert "/p#x/y" = render(parsed, %{frag: "x/y"})
    end

    test "fragment expansion encodes non-reserved (unicode)" do
      template = "/p{#frag}"

      assert {:ok, parsed} = parse_template(template)

      assert "/p#caf%C3%A9" = render(parsed, %{"frag" => "café"})
      assert "/p#caf%C3%A9" = render(parsed, %{frag: "café"})
    end

    test "label operator" do
      template = "/d{.label}"

      assert {:ok, parsed} = parse_template(template)

      assert "/d.example" = render(parsed, %{"label" => "example"})
      assert "/d.example" = render(parsed, %{label: "example"})
    end

    test "label operator encodes spaces" do
      template = "/d{.label}"

      assert {:ok, parsed} = parse_template(template)

      assert "/d.has%20dots" = render(parsed, %{"label" => "has dots"})
      assert "/d.has%20dots" = render(parsed, %{label: "has dots"})
    end

    test "path segment expansion with explode list" do
      template = "/api{/segments*}"

      assert {:ok, parsed} = parse_template(template)

      assert "/api/v1/users/42" = render(parsed, %{"segments" => ["v1", "users", "42"]})
      assert "/api/v1/users/42" = render(parsed, %{segments: ["v1", "users", "42"]})
    end

    test "path segment expansion without explode encodes slashes" do
      template = "/files{/path}"

      assert {:ok, parsed} = parse_template(template)

      assert "/files/a%2Fb%2Fc" = render(parsed, %{"path" => "a/b/c"})
      assert "/files/a%2Fb%2Fc" = render(parsed, %{path: "a/b/c"})
    end

    test "reserved path expansion keeps slashes" do
      template = "/files{+path}"

      assert {:ok, parsed} = parse_template(template)

      assert "/files/a/b/c" = render(parsed, %{"path" => "/a/b/c"})
      assert "/files/a/b/c" = render(parsed, %{path: "/a/b/c"})
    end

    test "no-operator variable list" do
      template = "/users/{id,name}"

      assert {:ok, parsed} = parse_template(template)

      assert "/users/42,alice" = render(parsed, %{"id" => "42", "name" => "alice"})
      assert "/users/42,alice" = render(parsed, %{id: "42", name: "alice"})
    end

    test "semicolon path-style parameter" do
      template = "/users{;id}"

      assert {:ok, parsed} = parse_template(template)

      assert "/users;id=42" = render(parsed, %{"id" => "42"})
      assert "/users;id=42" = render(parsed, %{id: "42"})
    end

    test "semicolon parameter with empty string" do
      template = "/users{;id}"

      assert {:ok, parsed} = parse_template(template)

      assert "/users;id" = render(parsed, %{"id" => ""})
      assert "/users;id" = render(parsed, %{id: ""})
    end

    test "semicolon parameter with exploded list" do
      template = "/m{;list*}"

      assert {:ok, parsed} = parse_template(template)

      assert "/m;list=a;list=b" = render(parsed, %{"list" => ["a", "b"]})
      assert "/m;list=a;list=b" = render(parsed, %{list: ["a", "b"]})
    end

    test "semicolon parameter with non-exploded list" do
      template = "/m{;list}"

      assert {:ok, parsed} = parse_template(template)

      assert "/m;list=a,b" = render(parsed, %{"list" => ["a", "b"]})
      assert "/m;list=a,b" = render(parsed, %{list: ["a", "b"]})
    end

    test "query form-style with single var" do
      template = "{?q}"

      assert {:ok, parsed} = parse_template(template)

      assert "?q=coffee" = render(parsed, %{"q" => "coffee"})
      assert "?q=coffee" = render(parsed, %{q: "coffee"})
    end

    test "query form-style with multiple vars and omission" do
      template = "{?x,y}"

      assert {:ok, parsed} = parse_template(template)

      assert "?x=1024&y=768" = render(parsed, %{"x" => "1024", "y" => "768"})
      assert "?x=1024" = render(parsed, %{"x" => "1024"})
    end

    test "query var with empty value is present" do
      template = "{?x}"

      assert {:ok, parsed} = parse_template(template)

      assert "?x=" = render(parsed, %{"x" => ""})
      assert "?x=" = render(parsed, %{x: ""})
    end

    test "query list non-exploded" do
      template = "{?list}"

      assert {:ok, parsed} = parse_template(template)

      assert "?list=red,green,blue" = render(parsed, %{"list" => ["red", "green", "blue"]})
      assert "?list=red,green,blue" = render(parsed, %{list: ["red", "green", "blue"]})
    end

    test "query list exploded" do
      template = "{?list*}"

      assert {:ok, parsed} = parse_template(template)

      assert "?list=red&list=green" = render(parsed, %{"list" => ["red", "green"]})
      assert "?list=red&list=green" = render(parsed, %{list: ["red", "green"]})
    end

    test "query continuation with &" do
      template = "?fixed=1{&x,y}"

      assert {:ok, parsed} = parse_template(template)

      assert "?fixed=1&x=2&y=3" = render(parsed, %{"x" => "2", "y" => "3"})
      assert "?fixed=1&x=2&y=3" = render(parsed, %{x: "2", y: "3"})
    end

    test "prefix modifier with simple expansion" do
      template = "/p/{var:3}"

      assert {:ok, parsed} = parse_template(template)

      assert "/p/abc" = render(parsed, %{"var" => "abcdef"})
      assert "/p/abc" = render(parsed, %{var: "abcdef"})
    end

    test "prefix modifier with reserved expansion" do
      template = "/base{+path:5}"

      assert {:ok, parsed} = parse_template(template)

      assert "/base/a/b/" = render(parsed, %{"path" => "/a/b/c"})
      assert "/base/a/b/" = render(parsed, %{path: "/a/b/c"})
    end

    test "unicode encoding in simple expansion" do
      template = "/q/{term}"

      assert {:ok, parsed} = parse_template(template)

      assert "/q/caf%C3%A9" = render(parsed, %{"term" => "café"})
      assert "/q/caf%C3%A9" = render(parsed, %{term: "café"})
    end

    test "unicode percent-encoded in reserved expansion" do
      template = "/u/{+term}"

      assert {:ok, parsed} = parse_template(template)

      # RFC 6570 requires non-ASCII characters to be UTF-8 percent-encoded even
      # in reserved ('+') expansions. Only ASCII reserved characters like '/'
      # may remain unencoded. "東京/渋谷" becomes "%E6%9D%B1%E4%BA%AC/%E6%B8%8B%E8%B0%B7".
      assert "/u/%E6%9D%B1%E4%BA%AC/%E6%B8%8B%E8%B0%B7" =
               render(parsed, %{"term" => "東京/渋谷"})

      assert "/u/%E6%9D%B1%E4%BA%AC/%E6%B8%8B%E8%B0%B7" = render(parsed, %{term: "東京/渋谷"})
    end

    test "emoji percent-encoding in query" do
      template = "{?emoji}"

      assert {:ok, parsed} = parse_template(template)

      assert "?emoji=%F0%9F%99%82" = render(parsed, %{"emoji" => "🙂"})
      assert "?emoji=%F0%9F%99%82" = render(parsed, %{emoji: "🙂"})
    end

    test "undefined variable omits entire expression in path" do
      template = "/users{/id}"

      assert {:ok, parsed} = parse_template(template)

      assert "/users" = render(parsed, %{})
      assert "/users" = render(parsed, %{})
    end

    test "empty string in simple expansion contributes nothing between literals" do
      template = "/a{empty}b"

      assert {:ok, parsed} = parse_template(template)

      assert "/ab" = render(parsed, %{"empty" => ""})
      assert "/ab" = render(parsed, %{empty: ""})
    end

    test "mixed expressions and literals" do
      template = "https://ex.com{/ver}{/res*}{?q,lang}{&page}"

      assert {:ok, parsed} = parse_template(template)

      assert "https://ex.com/v1/users/42?q=caf%C3%A9&lang=fr&page=2" =
               render(parsed, %{
                 "ver" => "v1",
                 "res" => ["users", "42"],
                 "q" => "café",
                 "lang" => "fr",
                 "page" => "2"
               })

      assert "https://ex.com/v1/users/42?q=caf%C3%A9&lang=fr&page=2" =
               render(parsed, %{
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

      assert "/t/0/false" = render(parsed, %{"num" => 0, "bool" => false})
      assert "/t/0/false" = render(parsed, %{num: 0, bool: false})
    end

    test "empty list omits query expression (exploded)" do
      template = "/s{?list*}"

      assert {:ok, parsed} = parse_template(template)

      assert "/s" = render(parsed, %{"list" => []})
      assert "/s" = render(parsed, %{list: []})
    end

    test "empty map omits semicolon parameter block" do
      template = "/p{;map*}"

      assert {:ok, parsed} = parse_template(template)

      assert "/p" = render(parsed, %{"map" => %{}})
      assert "/p" = render(parsed, %{map: %{}})
    end

    test "fragment with prefix modifier and unicode" do
      template = "{#frag:6}"

      assert {:ok, parsed} = parse_template(template)

      assert "#caf%C3%A9-b" = render(parsed, %{"frag" => "café-bar"})
      assert "#caf%C3%A9-b" = render(parsed, %{frag: "café-bar"})
    end

    test "exploded map query has no guaranteed order" do
      template = "/m{?map*}"

      assert {:ok, parsed} = parse_template(template)

      assert "/m?a=1&b=2" = render(parsed, %{"map" => %{"a" => "1", "b" => "2"}})

      assert "/m?a=1&b=2" = render(parsed, %{map: %{"a" => "1", "b" => "2"}})
    end

    test "exploded map with mixed atom and binary keys" do
      template = "https://ex.com{?map*}"

      assert {:ok, parsed} = parse_template(template)

      result = render(parsed, %{"map" => %{:a => 1, "b" => 2}})
      assert result in ["https://ex.com?a=1&b=2", "https://ex.com?b=2&a=1"]

      result2 = render(parsed, %{map: %{"a" => 1, :b => 2}})
      assert result2 in ["https://ex.com?a=1&b=2", "https://ex.com?b=2&a=1"]
    end

    test "exploding scalar values" do
      assert {:ok, parsed} = parse_template("/{int*}/{str*}{/null*}{?int*}{&str*}{&null*}")
      assert "/1/hello?int=1&str=hello" = render(parsed, %{int: 1, str: "hello", null: nil})
    end
  end

  describe "parsing invalid values" do
    test "unfinished expression" do
      assert {:error, {:invalid_value, "{aaa"}} = UriTemplate.parse("{aaa")
      assert {:error, {:invalid_value, "{aaa"}} = UriTemplate.parse("/{bbb}/{aaa")
    end

    test "invalid_operator" do
      assert {:error, {:invalid_value, "{$aaa}"}} = UriTemplate.parse("{$aaa}")
    end
  end

  describe "support for map and keywords" do
    test "default" do
      assert {:ok, parsed} = parse_template("{foo*}")
      assert "a=1,b=2" = render(parsed, %{"foo" => [{"a", "1"}, {"b", "2"}]})
      assert "a=1,b=2" = render(parsed, %{"foo" => [a: 1, b: 2]})
      assert "a=1,b=2" = render(parsed, %{"foo" => %{"a" => 1, "b" => 2}})
      assert "a=1,b=2" = render(parsed, %{"foo" => %{a: 1, b: 2}})
      assert "a=1,b=2" = render(parsed, %{foo: [{"a", "1"}, {"b", "2"}]})
      assert "a=1,b=2" = render(parsed, %{foo: [a: 1, b: 2]})
      assert "a=1,b=2" = render(parsed, %{foo: %{"a" => 1, "b" => 2}})
      assert "a=1,b=2" = render(parsed, %{foo: %{a: 1, b: 2}})

      # non exploded
      assert {:ok, parsed} = parse_template("{foo}")
      assert "a,1,b,2" = render(parsed, %{"foo" => [{"a", "1"}, {"b", "2"}]})
      assert "a,1,b,2" = render(parsed, %{"foo" => [a: 1, b: 2]})
      assert "a,1,b,2" = render(parsed, %{"foo" => %{"a" => 1, "b" => 2}})
      assert "a,1,b,2" = render(parsed, %{"foo" => %{a: 1, b: 2}})
      assert "a,1,b,2" = render(parsed, %{foo: [{"a", "1"}, {"b", "2"}]})
      assert "a,1,b,2" = render(parsed, %{foo: [a: 1, b: 2]})
      assert "a,1,b,2" = render(parsed, %{foo: %{"a" => 1, "b" => 2}})
      assert "a,1,b,2" = render(parsed, %{foo: %{a: 1, b: 2}})
    end
  end
end
