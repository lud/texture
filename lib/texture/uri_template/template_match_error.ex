defmodule Texture.UriTemplate.TemplateMatchError do
  @moduledoc """
  Error raised when a URL cannot be matched against a URI template.

  `Texture.UriTemplate.match!/2` raises this exception, and
  `Texture.UriTemplate.match/2` returns it in an `{:error, exception}` tuple.
  The `:url` field contains the URL that failed to match.
  """
  defexception [:message, :url]
end
