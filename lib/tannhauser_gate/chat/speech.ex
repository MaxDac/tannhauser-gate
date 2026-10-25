defmodule TannhauserGate.Chat.Speech do
  @moduledoc """
  Splits the text of an in-character entry into spoken words and action
  (narration) for the speech highlighting of the chat roleplay module.

  Text between double quotes (`“…”`, `"…"` or `«…»`, quotes included) is
  `:speech`, the rest is `:action`. The segments are plain strings: they are
  rendered as escaped text, never as HTML.
  """

  @quoted ~r/“[^”]*”|"[^"]*"|«[^»]*»/u
  @whole ~r/\A(?:“[^”]*”|"[^"]*"|«[^»]*»)\z/u

  @doc """
  Returns the `{:speech | :action, text}` segments of a text, in order.
  Empty segments are dropped; an unterminated quote is action.

      iex> segments(~s(She smiles. "Rain again." She leaves.))
      [{:action, "She smiles. "}, {:speech, ~s("Rain again.")}, {:action, " She leaves."}]
  """
  def segments(text) when is_binary(text) do
    @quoted
    |> Regex.split(text, include_captures: true, trim: true)
    |> Enum.map(&{if(Regex.match?(@whole, &1), do: :speech, else: :action), &1})
  end

  def segments(_), do: []
end
