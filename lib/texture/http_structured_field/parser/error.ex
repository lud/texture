defmodule Texture.HttpStructuredField.Parser.Error do
  @moduledoc """
  Exception raised when a structured field cannot be parsed.

  The exception carries the following fields:

  * `:reason` - a `{tag, rest}` tuple where `tag` is an atom describing the
    error (for instance `:invalid_value` or `:expected_delimiter`) and `rest`
    is the remaining input at the point of failure.
  * `:value` - the full value given to the parser.
  """

  defexception [:reason, :value]

  @type t :: %__MODULE__{reason: {atom, binary}, value: binary | nil}

  @impl true
  def message(%__MODULE__{reason: reason, value: value}) do
    "could not parse structured field value #{inspect(value)}, got: #{inspect(reason)}"
  end
end
