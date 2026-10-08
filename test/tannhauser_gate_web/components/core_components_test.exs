defmodule TannhauserGateWeb.CoreComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias TannhauserGateWeb.CoreComponents

  test "text-like inputs preserve labels, values and native attributes" do
    for type <- ~w(text email password number) do
      document =
        input_document(
          id: "field",
          name: "record[value]",
          value: "42",
          type: type,
          label: "Value",
          required: true,
          readonly: true,
          autocomplete: "off"
        )

      assert_element(document, "label[for='field'] .console-label")

      assert_element(
        document,
        "#field.console-field[type='#{type}'][name='record[value]'][value='42'][required][readonly][autocomplete='off']"
      )

      refute_element(document, "#field[aria-invalid]")
      refute_element(document, "#field-errors")
    end
  end

  test "all visible control types associate errors and preserve existing descriptions" do
    for type <- ~w(text textarea select checkbox file) do
      document =
        input_document(
          id: "field",
          name: "value",
          value: nil,
          type: type,
          options: [{"One", "1"}],
          errors: ["is invalid", "is required"],
          "aria-describedby": "existing-help"
        )

      assert_element(
        document,
        "#field[aria-invalid='true'][aria-describedby='existing-help field-errors']"
      )

      assert length(LazyHTML.to_tree(LazyHTML.query(document, "#field-errors p"))) == 2
    end
  end

  test "textarea and select retain content, rows, prompt, multiple and selected values" do
    document =
      input_document(
        id: "body",
        name: "body",
        value: "A rainy night",
        type: "textarea",
        rows: "8"
      )

    assert_element(document, "textarea#body.textarea.console-field[rows='8']")
    assert LazyHTML.text(LazyHTML.query(document, "#body")) == "A rainy night"

    document =
      input_document(
        id: "story",
        name: "story[]",
        value: ["2"],
        type: "select",
        multiple: true,
        prompt: "Choose",
        options: [{"One", "1"}, {"Two", "2"}]
      )

    assert_element(document, "#story.select.console-field[multiple]")
    assert_element(document, "#story option[value='']")
    refute_element(document, "#story option[value=''][selected]")
    assert_element(document, "#story option[value='2'][selected]")
  end

  test "checkbox retains checked state and disabled hidden false value" do
    document =
      input_document(
        id: "remember",
        name: "remember",
        value: true,
        type: "checkbox",
        label: "Remember me",
        disabled: true,
        form: "login"
      )

    assert_element(document, "#remember.console-check[checked][disabled][form='login']")
    assert_element(document, "input[type='hidden'][name='remember'][value='false'][disabled]")
    assert_element(document, "label[for='remember']")
  end

  test "class and error class overrides still replace defaults" do
    for type <- ~w(text textarea select checkbox) do
      document =
        input_document(
          id: "custom",
          name: "value",
          value: nil,
          type: type,
          options: [],
          class: "custom-control",
          error_class: "custom-error",
          errors: ["is invalid"]
        )

      assert_element(document, "#custom.custom-control.custom-error[aria-invalid='true']")
      refute_element(document, "#custom.console-field, #custom.console-check")
    end
  end

  test "file input uses file styling and hidden input remains unstyled" do
    document =
      input_document(id: "upload", name: "upload", value: nil, type: "file", accept: ".png")

    assert_element(document, "#upload.file-input.console-field[accept='.png']")

    document = input_document(id: "token", name: "token", value: "secret", type: "hidden")
    assert_element(document, "#token[type='hidden'][value='secret']")
    refute_element(document, ".console-field, .console-fieldset")
  end

  test "errors on unused form fields remain hidden until the field is used" do
    for {params, errors_visible?} <- [
          {%{"name" => "", "_unused_name" => ""}, false},
          {%{"name" => ""}, true}
        ] do
      form =
        Phoenix.Component.to_form(params,
          as: :character,
          errors: [name: {"can't be blank", []}]
        )

      document = input_document(field: form[:name])

      if errors_visible? do
        assert_element(document, "#character_name[aria-invalid='true']")
        assert_element(document, "#character_name-errors")
      else
        refute_element(document, "#character_name[aria-invalid]")
        refute_element(document, "#character_name-errors")
      end
    end
  end

  test "buttons preserve native actions, variants and explicit class overrides" do
    slot = [%{inner_block: fn _, _ -> "Save" end}]

    document =
      render_component(&CoreComponents.button/1,
        id: "save",
        variant: "primary",
        disabled: true,
        "phx-disable-with": "Saving...",
        inner_block: slot
      )
      |> LazyHTML.from_fragment()

    assert_element(
      document,
      "#save.btn-primary.console-action[disabled][phx-disable-with='Saving...']"
    )

    document =
      render_component(&CoreComponents.button/1,
        id: "cancel",
        href: "/",
        class: "custom-action",
        inner_block: slot
      )
      |> LazyHTML.from_fragment()

    assert_element(document, "a#cancel.custom-action[href='/']")
    refute_element(document, "#cancel.console-action")
  end

  defp input_document(assigns) do
    render_component(&CoreComponents.input/1, assigns)
    |> LazyHTML.from_fragment()
  end

  defp assert_element(document, selector) do
    assert [_ | _] = document |> LazyHTML.query(selector) |> LazyHTML.to_tree()
  end

  defp refute_element(document, selector) do
    assert [] = document |> LazyHTML.query(selector) |> LazyHTML.to_tree()
  end
end
