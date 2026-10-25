defmodule TannhauserGateWeb.TranslationCatalogTest do
  use ExUnit.Case, async: true

  @catalog_root Path.expand("../../priv/gettext", __DIR__)

  for locale <- ~w(it es pt_PT) do
    test "#{locale} has complete, non-fuzzy catalogs with matching interpolation bindings" do
      templates = Path.wildcard(Path.join(@catalog_root, "*.pot"))
      assert templates != []

      for template <- templates do
        domain = Path.basename(template, ".pot")
        path = Path.join([@catalog_root, unquote(locale), "LC_MESSAGES", domain <> ".po"])
        assert File.exists?(path), "Missing catalog: #{path}"

        translated =
          path
          |> Expo.PO.parse_file!()
          |> Map.fetch!(:messages)
          |> Enum.reject(& &1.obsolete)
          |> Map.new(&{message_key(&1), &1})

        for source <- Expo.PO.parse_file!(template).messages do
          key = message_key(source)
          assert Map.has_key?(translated, key), "Missing #{inspect(key)} in #{path}"
          message = Map.fetch!(translated, key)
          refute Expo.Message.has_flag?(message, "fuzzy"), "Fuzzy #{inspect(key)} in #{path}"

          forms =
            case message do
              %Expo.Message.Plural{msgstr: forms} ->
                assert Map.has_key?(forms, 0) and Map.has_key?(forms, 1)
                Map.values(forms)

              %Expo.Message.Singular{msgstr: form} ->
                [form]
            end

          for form <- forms do
            text = IO.iodata_to_binary(form)
            assert String.trim(text) != "", "Empty #{inspect(key)} in #{path}"

            assert bindings(text) == bindings(IO.iodata_to_binary(source.msgid)),
                   "Mismatched bindings for #{inspect(key)} in #{path}"
          end
        end
      end
    end
  end

  defp message_key(message), do: {message.msgctxt, IO.iodata_to_binary(message.msgid)}

  defp bindings(text) do
    ~r/%\{(\w+)\}/
    |> Regex.scan(text, capture: :all_but_first)
    |> List.flatten()
    |> MapSet.new()
  end
end
