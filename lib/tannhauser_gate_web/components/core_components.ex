defmodule TannhauserGateWeb.CoreComponents do
  @moduledoc """
  Provides core UI components.

  At first glance, this module may seem daunting, but its goal is to provide
  core building blocks for your application, such as tables, forms, and
  inputs. The components consist mostly of markup and are well-documented
  with doc strings and declarative assigns. You may customize and style
  them in any way you want, based on your application growth and needs.

  The foundation for styling is Tailwind CSS, a utility-first CSS framework,
  augmented with daisyUI, a Tailwind CSS plugin that provides UI components
  and themes. Here are useful references:

    * [daisyUI](https://daisyui.com/docs/intro/) - a good place to get
      started and see the available components.

    * [Tailwind CSS](https://tailwindcss.com) - the foundational framework
      we build on. You will use it for layout, sizing, flexbox, grid, and
      spacing.

    * [Heroicons](https://heroicons.com) - see `icon/1` for usage.

    * [Phoenix.Component](https://phoenix-live-view.hexdocs.pm/Phoenix.Component.html) -
      the component system used by Phoenix. Some components, such as `<.link>`
      and `<.form>`, are defined there.

  """
  use Phoenix.Component
  use Gettext, backend: TannhauserGateWeb.Gettext

  alias Phoenix.HTML.Form
  alias Phoenix.LiveView.JS
  alias TannhauserGate.Stories.Themes

  @doc "The GDR appearance editor, using the same controls as the rest of the application."
  attr :form, Phoenix.HTML.Form, required: true

  def appearance_editor(assigns) do
    assigns =
      assigns
      |> assign(:themes, Themes.all())
      |> assign(:selected, assigns.form[:theme].value)
      |> assign(:overrides, assigns.form[:theme_overrides].value || %{})
      |> assign(:controls, assigns.form[:control_style].value || %{})

    ~H"""
    <div class="space-y-6">
      <.form for={@form} id="theme-form" phx-change="validate_story" phx-submit="save_story">
        <div class="rounded-xl border border-base-content/10 bg-base-200/60 p-5 sm:p-6">
          <div class="mb-5">
            <h2 class="text-lg font-semibold text-base-content">{dgettext("shared", "Make it your world")}</h2>
            <p class="mt-1 text-sm text-fog-400">
              {dgettext("shared", "Eight identities, one design system. Every preset is available to every GDR.")}
            </p>
          </div>
          <div id="theme-presets" class="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
            <.theme_card :for={theme <- @themes} theme={theme} selected={@selected == theme.id} />
          </div>
          <div class="mt-5 grid gap-x-5 sm:grid-cols-2 lg:grid-cols-4">
            <.input field={@form[:theme]} type="select" label={dgettext("shared", "Preset")} options={Themes.options()} />
            <.input
              :for={{key, label} <- [
                {"corners", dgettext("shared", "Corners")},
                {"density", dgettext("shared", "Density")},
                {"effects", dgettext("shared", "Effects")}
              ]}
              type="select"
              id={"control-#{key}"}
              name={"story[control_style][#{key}]"}
              label={label}
              value={@controls[key]}
              prompt={dgettext("shared", "Use preset default")}
              options={Themes.control_options()[key]}
            />
          </div>
          <div :if={@form[:control_style].errors != []} id="control-style-errors" role="alert">
            <.error :for={error <- @form[:control_style].errors}>{translate_error(error)}</.error>
          </div>
          <details id="theme-colours" class="mt-4 rounded-xl border border-base-content/10 p-4">
            <summary class="cursor-pointer text-sm font-medium text-base-content">
              {dgettext("shared", "Custom colours")}
              <span class="ml-2 text-xs font-normal text-fog-400">{dgettext("shared", "Optional hex overrides")}</span>
            </summary>
            <p class="mt-3 text-xs text-fog-400">
              {dgettext("shared", "Leave a field empty to inherit the preset. Button text adjusts to the chosen colour.")}
            </p>
            <div class="mt-3 grid gap-x-5 sm:grid-cols-2 lg:grid-cols-4">
              <.input
                :for={key <- Themes.color_keys()}
                type="text"
                id={"override-#{key}"}
                name={"story[theme_overrides][#{key}]"}
                value={@overrides[key]}
                label={key}
                placeholder={Themes.palette(@selected)[key]}
                pattern="#[0-9a-fA-F]{6}"
                maxlength="7"
                phx-debounce="250"
              />
            </div>
          </details>
          <div class="mt-5 flex flex-wrap items-center justify-between gap-3">
            <p class="text-xs text-fog-400">{dgettext("shared", "Changes below are a preview until you save.")}</p>
            <div class="flex gap-2">
              <.button id="theme-reset" type="button" variant="ghost" phx-click="reset_theme">
                {dgettext("shared", "Reset to preset")}
              </.button>
              <.button id="theme-save" variant="primary" phx-disable-with={dgettext("shared", "Saving...")}>
                {dgettext("shared", "Save theme")}
              </.button>
            </div>
          </div>
        </div>
      </.form>
      <.appearance_preview theme={@selected} overrides={@overrides} controls={@controls} />
    </div>
    """
  end

  @doc "A selectable GDR preset card. Selection is handled by the owning LiveView."
  attr :theme, :map, required: true
  attr :selected, :boolean, default: false

  def theme_card(assigns) do
    ~H"""
    <button
      id={"theme-preset-#{@theme.id}"}
      type="button"
      phx-click="preview_theme"
      phx-value-theme={@theme.id}
      aria-pressed={to_string(@selected)}
      class={[
        "theme-preset rounded-xl border p-4 text-left transition-colors focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-primary",
        if(@selected,
          do: "border-primary/70 bg-primary/10",
          else: "border-base-content/15 bg-base-200/50 hover:border-primary/40"
        )
      ]}
    >
      <span class="mb-3 flex gap-1.5" aria-hidden="true">
        <span
          :for={color <- Enum.take(@theme.colors, -3)}
          class="size-3 rounded-full ring-1 ring-white/10"
          style={"background-color:#{color}"}
        />
      </span>
      <span class="block text-sm font-semibold text-base-content">{@theme.name}</span>
      <span :if={@theme.game} class="mt-1 block text-xs text-secondary">{@theme.game}</span>
      <span class="mt-2 block text-xs leading-relaxed text-fog-400">{@theme.description}</span>
    </button>
    """
  end

  @doc "A scoped, unsaved preview of the shared controls and a long chat entry."
  attr :theme, :string, required: true
  attr :overrides, :map, default: %{}
  attr :controls, :map, default: %{}

  def appearance_preview(assigns) do
    ~H"""
    <section
      id="theme-preview"
      data-theme={@theme}
      style={Themes.style(@theme, @overrides, @controls)}
      class="overflow-hidden rounded-xl border border-base-content/15 bg-base-100 text-base-content"
      aria-label={dgettext("shared", "Unsaved appearance preview")}
    >
      <div class="border-b border-base-content/10 px-5 py-4">
        <h2 class="font-semibold">
          {dgettext("shared", "Live preview")} <span class="ml-2 text-xs font-normal text-fog-400">{dgettext("shared", "Not saved")}</span>
        </h2>
        <p
          :for={warning <- Themes.contrast_warnings(@theme, @overrides)}
          class="mt-2 text-sm text-warning"
          role="status"
        >
          {warning}
        </p>
      </div>
      <div class="grid lg:grid-cols-2">
        <div class="space-y-4 border-b border-base-content/10 p-5 lg:border-r lg:border-b-0">
          <div class="flex flex-wrap gap-2">
            <.button id="preview-primary" type="button" variant="primary">{dgettext("shared", "Primary action")}</.button>
            <.button id="preview-secondary" type="button" variant="secondary">{dgettext("shared", "Secondary")}</.button>
            <.button id="preview-ghost" type="button" variant="ghost">{dgettext("shared", "Quiet action")}</.button>
            <.button id="preview-danger" type="button" variant="danger">{dgettext("shared", "Destructive")}</.button>
            <.button id="preview-disabled" type="button" disabled>{dgettext("shared", "Unavailable")}</.button>
          </div>
          <.input
            id="preview-input"
            name="preview-input"
            value=""
            label={dgettext("shared", "Character name")}
            placeholder="Mara Voss"
          />
          <.input
            id="preview-select"
            name="preview-select"
            value="speech"
            type="select"
            label={dgettext("shared", "Message type")}
            options={[{dgettext("shared", "In character"), "speech"}, {dgettext("management", "OFF"), "ooc"}, {dgettext("shared", "Whisper"), "whisper"}]}
          />
          <.input
            id="preview-check"
            name="preview-check"
            value={true}
            type="checkbox"
            label={dgettext("shared", "Show action tags")}
          />
          <.input
            id="preview-error"
            name="preview-error"
            value=""
            label={dgettext("shared", "Validation example")}
            errors={[dgettext("shared", "Choose a valid value")]}
          />
        </div>
        <div class="p-5">
          <div class="flex items-start gap-3">
            <TannhauserGateWeb.GameComponents.avatar
              character={%{name: "Mara Voss", avatar_path: nil}}
              class="size-11 shrink-0"
            />
            <div class="min-w-0 flex-1">
              <div class="flex flex-wrap items-baseline gap-x-3">
                <span class="font-semibold text-primary">Mara Voss</span>
                <time class="text-xs text-fog-400" datetime="2121-11-03T21:01:00Z">2121-11-03 21:01</time>
              </div>
              <TannhauserGateWeb.ChatComponents.chat_body
                id="preview-chat-body"
                tag={dgettext("management", "at the counter")}
                highlight
                body={dgettext("management", "Mara places a brass key beside her untouched bowl and glances towards the door.\n\n\"The station was empty. No guards, no passengers. But the departures board was counting down to a train that wasn't on any schedule.\"\n\nShe lowers her voice. \"Tell me you found something better than another locked office.\"")}
                class="mt-2 text-sm leading-relaxed"
              />
            </div>
          </div>
          <div class="mt-5 border-t border-base-content/10 pt-4">
            <.input
              id="preview-message"
              name="preview-message"
              value=""
              type="textarea"
              label={dgettext("shared", "Message")}
              placeholder={dgettext("shared", "Let the scene unfold...")}
              rows="3"
            />
            <div class="flex justify-end">
              <.button id="preview-send" type="button" variant="primary" size="sm">
                {dgettext("shared", "Send message")} <.icon name="hero-arrow-right-micro" class="size-4" />
              </.button>
            </div>
          </div>
        </div>
      </div>
    </section>
    """
  end

  @doc """
  Renders flash notices.

  ## Examples

      <.flash kind={:info} flash={@flash} />
      <.flash
        id="welcome-back"
        kind={:info}
        phx-mounted={show("#welcome-back") |> JS.remove_attribute("hidden")}
        hidden
      >
        Welcome Back!
      </.flash>
  """
  attr :id, :string, doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup"
  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"

  slot :inner_block, doc: "the optional inner block that renders the flash message"

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      role="alert"
      class="toast toast-top toast-end z-50"
      {@rest}
    >
      <div class={[
        "alert w-80 sm:w-96 max-w-80 sm:max-w-96 text-wrap",
        @kind == :info && "alert-info",
        @kind == :error && "alert-error"
      ]}>
        <.icon :if={@kind == :info} name="hero-information-circle" class="size-5 shrink-0" />
        <.icon :if={@kind == :error} name="hero-exclamation-circle" class="size-5 shrink-0" />
        <div>
          <p :if={@title} class="font-semibold">{@title}</p>
          <p>{msg}</p>
        </div>
        <div class="flex-1" />
        <button
          type="button"
          class="group self-start cursor-pointer"
          aria-label={dgettext("shared", "close")}
        >
          <.icon name="hero-x-mark" class="size-5 opacity-40 group-hover:opacity-70" />
        </button>
      </div>
    </div>
    """
  end

  @doc """
  Renders a button with navigation support.

  ## Examples

      <.button>Send!</.button>
      <.button phx-click="go" variant="primary">Send!</.button>
      <.button navigate={~p"/"}>Home</.button>
  """
  attr :rest, :global, include: ~w(href navigate patch method download name value disabled type)
  attr :class, :any
  attr :variant, :string, values: ~w(primary secondary ghost danger)
  attr :size, :string, default: "md", values: ~w(xs sm md lg)
  slot :inner_block, required: true

  def button(%{rest: rest} = assigns) do
    variants = %{
      "primary" => "btn-primary",
      "secondary" => "btn-soft btn-primary",
      "ghost" => "btn-ghost",
      "danger" => "btn-soft btn-error",
      nil => "btn-soft btn-primary"
    }

    assigns =
      assign_new(assigns, :class, fn ->
        ["btn console-action", "btn-#{assigns.size}", Map.fetch!(variants, assigns[:variant])]
      end)

    if rest[:href] || rest[:navigate] || rest[:patch] do
      ~H"""
      <.link class={@class} {@rest}>
        {render_slot(@inner_block)}
      </.link>
      """
    else
      ~H"""
      <button class={@class} {@rest}>
        {render_slot(@inner_block)}
      </button>
      """
    end
  end

  @doc """
  Renders an input with label and error messages.

  A `Phoenix.HTML.FormField` may be passed as argument,
  which is used to retrieve the input name, id, and values.
  Otherwise all attributes may be passed explicitly.

  ## Types

  This function accepts all HTML input types, considering that:

    * You may also set `type="select"` to render a `<select>` tag

    * `type="checkbox"` is used exclusively to render boolean values

    * For live file uploads, see `Phoenix.Component.live_file_input/1`

  See https://developer.mozilla.org/en-US/docs/Web/HTML/Element/input
  for more information. Unsupported types, such as radio, are best
  written directly in your templates.

  ## Examples

  ```heex
  <.input field={@form[:email]} type="email" />
  <.input name="my-input" errors={["oh no!"]} />
  ```

  ## Select type

  When using `type="select"`, you must pass the `options` and optionally
  a `value` to mark which option should be preselected.

  ```heex
  <.input field={@form[:user_type]} type="select" options={["Admin": "admin", "User": "user"]} />
  ```

  For more information on what kind of data can be passed to `options` see
  [`options_for_select`](https://phoenix-html.hexdocs.pm/Phoenix.HTML.Form.html#options_for_select/2).
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any

  attr :type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file month number password
               search select tel text textarea time url week hidden)

  attr :field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :list, default: []
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"
  attr :options, :list, doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2"
  attr :multiple, :boolean, default: false, doc: "the multiple flag for select inputs"
  attr :class, :any, default: nil, doc: "the input class to use over defaults"
  attr :error_class, :any, default: nil, doc: "the input error class to use over defaults"

  attr :rest, :global,
    include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step)

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "hidden"} = assigns) do
    ~H"""
    <input type="hidden" id={@id} name={@name} value={@value} {@rest} />
    """
  end

  def input(%{type: "checkbox"} = assigns) do
    assigns =
      assigns
      |> assign_input_accessibility()
      |> assign_new(:checked, fn ->
        Form.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <div class="fieldset console-fieldset mb-2">
      <label for={@id}>
        <input
          type="hidden"
          name={@name}
          value="false"
          disabled={@rest[:disabled]}
          form={@rest[:form]}
        />
        <span class="label gap-3 text-sm text-base-content">
          <input
            type="checkbox"
            id={@id}
            name={@name}
            value="true"
            checked={@checked}
            class={[
              @class || "checkbox checkbox-sm console-check",
              @errors != [] && (@error_class || "checkbox-error")
            ]}
            {@rest}
          />{@label}
        </span>
      </label>
      <div :if={@errors != []} id={@error_id}>
        <.error :for={msg <- @errors}>{msg}</.error>
      </div>
    </div>
    """
  end

  def input(%{type: "select"} = assigns) do
    assigns = assign_input_accessibility(assigns)

    ~H"""
    <div class="fieldset console-fieldset mb-2">
      <label for={@id}>
        <span
          :if={@label}
          class="label console-label"
        >{@label}</span>
        <select
          id={@id}
          name={@name}
          class={[
            @class || "w-full select console-field",
            @errors != [] && (@error_class || "select-error")
          ]}
          multiple={@multiple}
          {@rest}
        >
          <option :if={@prompt} value="">{@prompt}</option>
          {Form.options_for_select(@options, @value)}
        </select>
      </label>
      <div :if={@errors != []} id={@error_id}>
        <.error :for={msg <- @errors}>{msg}</.error>
      </div>
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    assigns = assign_input_accessibility(assigns)

    ~H"""
    <div class="fieldset console-fieldset mb-2">
      <label for={@id}>
        <span
          :if={@label}
          class="label console-label"
        >{@label}</span>
        <textarea
          id={@id}
          name={@name}
          class={[
            @class || "w-full textarea console-field",
            @errors != [] && (@error_class || "textarea-error")
          ]}
          {@rest}
        >{Form.normalize_value("textarea", @value)}</textarea>
      </label>
      <div :if={@errors != []} id={@error_id}>
        <.error :for={msg <- @errors}>{msg}</.error>
      </div>
    </div>
    """
  end

  # All other inputs text, datetime-local, url, password, etc. are handled here...
  def input(assigns) do
    assigns = assign_input_accessibility(assigns)

    ~H"""
    <div class="fieldset console-fieldset mb-2">
      <label for={@id}>
        <span
          :if={@label}
          class="label console-label"
        >{@label}</span>
        <input
          type={@type}
          name={@name}
          id={@id}
          value={Form.normalize_value(@type, @value)}
          class={[
            @class ||
              if(@type == "file",
                do: "w-full file-input console-field",
                else: "w-full input console-field"
              ),
            @errors != [] &&
              (@error_class ||
                 if(@type == "file", do: "file-input-error", else: "input-error"))
          ]}
          {@rest}
        />
      </label>
      <div :if={@errors != []} id={@error_id}>
        <.error :for={msg <- @errors}>{msg}</.error>
      </div>
    </div>
    """
  end

  defp assign_input_accessibility(assigns) do
    error_id = if assigns.id && assigns.errors != [], do: "#{assigns.id}-errors"

    rest =
      if assigns.errors != [] do
        rest = Map.put(assigns.rest, :"aria-invalid", "true")

        if error_id do
          described_by =
            [rest[:"aria-describedby"], error_id]
            |> Enum.reject(&is_nil/1)
            |> Enum.join(" ")

          Map.put(rest, :"aria-describedby", described_by)
        else
          rest
        end
      else
        assigns.rest
      end

    assign(assigns, error_id: error_id, rest: rest)
  end

  @doc """
  Renders an error message, used by inputs and for form-level errors.
  """
  slot :inner_block, required: true

  def error(assigns) do
    ~H"""
    <p class="mt-1.5 flex gap-2 items-center text-sm text-error">
      <.icon name="hero-exclamation-circle" class="size-5" />
      {render_slot(@inner_block)}
    </p>
    """
  end

  @doc """
  Renders a header with title.
  """
  attr :class, :any, default: nil
  slot :inner_block, required: true
  slot :subtitle
  slot :actions

  def header(assigns) do
    ~H"""
    <header class={[@actions != [] && "flex items-center justify-between gap-6", "pb-4", @class]}>
      <div>
        <h1 class="phosphor-text text-2xl font-semibold leading-8 tracking-wide text-primary">
          {render_slot(@inner_block)}
        </h1>
        <p :if={@subtitle != []} class="mt-2 text-sm text-fog-400">
          {render_slot(@subtitle)}
        </p>
      </div>
      <div class="flex-none">{render_slot(@actions)}</div>
    </header>
    """
  end

  @doc """
  Renders a table with generic styling.

  ## Examples

      <.table id="users" rows={@users}>
        <:col :let={user} label="id">{user.id}</:col>
        <:col :let={user} label="username">{user.username}</:col>
      </.table>
  """
  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :row_id, :any, default: nil, doc: "the function for generating the row id"
  attr :row_click, :any, default: nil, doc: "the function for handling phx-click on each row"

  attr :row_item, :any,
    default: &Function.identity/1,
    doc: "the function for mapping each row before calling the :col and :action slots"

  slot :col, required: true do
    attr :label, :string
  end

  slot :action, doc: "the slot for showing user actions in the last table column"

  def table(assigns) do
    assigns =
      with %{rows: %Phoenix.LiveView.LiveStream{}} <- assigns do
        assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
      end

    ~H"""
    <div class="overflow-x-auto">
      <table class="table table-zebra">
        <thead>
          <tr>
            <th :for={col <- @col}>{col[:label]}</th>
            <th :if={@action != []}>
              <span class="sr-only">{dgettext("shared", "Actions")}</span>
            </th>
          </tr>
        </thead>
        <tbody id={@id} phx-update={is_struct(@rows, Phoenix.LiveView.LiveStream) && "stream"}>
          <tr :for={row <- @rows} id={@row_id && @row_id.(row)}>
            <td
              :for={col <- @col}
              phx-click={@row_click && @row_click.(row)}
              class={@row_click && "hover:cursor-pointer"}
            >
              {render_slot(col, @row_item.(row))}
            </td>
            <td :if={@action != []} class="w-0 font-semibold">
              <div class="flex gap-4">
                <%= for action <- @action do %>
                  {render_slot(action, @row_item.(row))}
                <% end %>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  @doc """
  Renders a data list.

  ## Examples

      <.list>
        <:item title="Title">{@post.title}</:item>
        <:item title="Views">{@post.views}</:item>
      </.list>
  """
  slot :item, required: true do
    attr :title, :string, required: true
  end

  def list(assigns) do
    ~H"""
    <ul class="list">
      <li :for={item <- @item} class="list-row">
        <div class="list-col-grow">
          <div class="font-bold">{item.title}</div>
          <div>{render_slot(item)}</div>
        </div>
      </li>
    </ul>
    """
  end

  @doc """
  Renders a [Heroicon](https://heroicons.com).

  Heroicons come in three styles – outline, solid, and mini.
  By default, the outline style is used, but solid and mini may
  be applied by using the `-solid` and `-mini` suffix.

  You can customize the size and colors of the icons by setting
  width, height, and background color classes.

  Icons are extracted from the `deps/heroicons` directory and bundled within
  your compiled app.css by the plugin in `assets/vendor/heroicons.js`.

  ## Examples

      <.icon name="hero-x-mark" />
      <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
  """
  attr :name, :string, required: true
  attr :class, :any, default: "size-4"

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end

  ## JS Commands

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      time: 300,
      transition:
        {"transition-all ease-out duration-300",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all ease-in duration-200", "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end

  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    if count = opts[:count] do
      Gettext.dngettext(TannhauserGateWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(TannhauserGateWeb.Gettext, "errors", msg, opts)
    end
  end

  @doc """
  Translates the errors for a field from a keyword list of errors.
  """
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end
end
