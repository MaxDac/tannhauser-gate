defmodule TannhauserGateWeb.GmLive.Guide do
  @moduledoc "GM config: the GDR admin writes the guide (sections and Markdown pages)."
  use TannhauserGateWeb, :live_view

  import TannhauserGateWeb.GmNav

  alias TannhauserGate.Guide
  alias TannhauserGate.Guide.{Page, Section}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "GM dashboard")
     |> reload()
     |> edit_section(%Section{})
     |> assign(page: nil, page_form: nil, preview: "")}
  end

  defp story(socket), do: socket.assigns.current_story

  defp reload(socket), do: assign(socket, :sections, Guide.list_sections(story(socket)))

  defp edit_section(socket, section) do
    assign(socket, section: section, section_form: to_form(Guide.change_section(section)))
  end

  defp edit_page(socket, page) do
    assign(socket,
      page: page,
      page_form: to_form(Guide.change_page(page)),
      preview: page.body || ""
    )
  end

  @impl true
  def handle_event("save_section", %{"section" => params}, socket) do
    result =
      case socket.assigns.section do
        %Section{id: nil} -> Guide.create_section(story(socket), params)
        section -> Guide.update_section(section, params)
      end

    case result do
      {:ok, _} ->
        {:noreply,
         socket |> put_flash(:info, "Section saved.") |> reload() |> edit_section(%Section{})}

      {:error, changeset} ->
        {:noreply, assign(socket, :section_form, to_form(changeset))}
    end
  end

  def handle_event("edit_section", %{"id" => id}, socket) do
    {:noreply, edit_section(socket, Guide.get_section!(story(socket), id))}
  end

  def handle_event("cancel_section", _, socket), do: {:noreply, edit_section(socket, %Section{})}

  def handle_event("delete_section", %{"id" => id}, socket) do
    {:ok, _} = story(socket) |> Guide.get_section!(id) |> Guide.delete_section()

    {:noreply,
     socket
     |> put_flash(:info, "Section deleted.")
     |> reload()
     |> edit_section(%Section{})
     |> assign(page: nil, page_form: nil)}
  end

  def handle_event("new_page", %{"section-id" => section_id}, socket) do
    section = Guide.get_section!(story(socket), section_id)

    {:noreply,
     edit_page(socket, %Page{section_id: section.id, position: length(pages(socket, section.id))})}
  end

  def handle_event("edit_page", %{"id" => id}, socket) do
    {:noreply, edit_page(socket, Guide.get_page!(story(socket), id))}
  end

  def handle_event("cancel_page", _, socket),
    do: {:noreply, assign(socket, page: nil, page_form: nil)}

  def handle_event("validate_page", %{"page" => params}, socket) do
    form = socket.assigns.page |> Guide.change_page(params) |> Map.put(:action, :validate)
    {:noreply, assign(socket, page_form: to_form(form), preview: params["body"] || "")}
  end

  def handle_event("save_page", %{"page" => params}, socket) do
    result =
      case socket.assigns.page do
        %Page{id: nil} = page ->
          Guide.create_page(story(socket), Map.put_new(params, "section_id", page.section_id))

        page ->
          Guide.update_page(story(socket), page, params)
      end

    case result do
      {:ok, page} ->
        {:noreply, socket |> put_flash(:info, "Page saved.") |> reload() |> edit_page(page)}

      {:error, changeset} ->
        {:noreply, assign(socket, :page_form, to_form(changeset))}
    end
  end

  def handle_event("delete_page", %{"id" => id}, socket) do
    {:ok, _} = story(socket) |> Guide.get_page!(id) |> Guide.delete_page()

    {:noreply,
     socket |> put_flash(:info, "Page deleted.") |> reload() |> assign(page: nil, page_form: nil)}
  end

  defp pages(socket, section_id) do
    case Enum.find(socket.assigns.sections, &(&1.id == section_id)) do
      nil -> []
      section -> section.pages
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      current_path={@current_path}
      current_story={@current_story}
      story_role={@story_role}
      online={@online}
      last_location={@last_location}
      mail_unread={@mail_unread}
    >
      <.gm_header story={@current_story} />
      <.gm_tabs story={@current_story} tab="guide" />

      <div class="mt-6 grid gap-6 xl:grid-cols-[22rem_1fr]">
        <section id="guide-sections" class="space-y-4">
          <div class="rounded-xl border border-secondary/20 bg-base-200/80 p-4">
            <h2 class="text-sm font-bold uppercase tracking-[0.2em] text-secondary">
              {if @section.id, do: "Edit section", else: "New section"}
            </h2>
            <.form for={@section_form} id="section-form" phx-submit="save_section" class="mt-2">
              <.input field={@section_form[:title]} type="text" label="Title" required />
              <.input field={@section_form[:position]} type="number" label="Position" min="0" />
              <div class="flex gap-2">
                <.button id="save-section" phx-disable-with="Saving...">Save section</.button>
                <.button
                  :if={@section.id}
                  type="button"
                  id="cancel-section"
                  phx-click="cancel_section"
                >
                  Cancel
                </.button>
              </div>
            </.form>
          </div>

          <p :if={@sections == []} id="guide-sections-empty" class="text-sm text-base-content/60">
            The guide is empty: add a section, then its pages.
          </p>

          <div
            :for={section <- @sections}
            id={"guide-section-#{section.id}"}
            class="rounded-xl border border-secondary/20 bg-base-200/60 p-4"
          >
            <div class="flex items-center justify-between gap-2">
              <h3 class="font-semibold text-primary">{section.title}</h3>
              <div class="flex gap-1">
                <button
                  id={"edit-section-#{section.id}"}
                  phx-click="edit_section"
                  phx-value-id={section.id}
                  class="rounded p-1 text-base-content/60 transition-colors hover:text-secondary"
                  title="Edit section"
                >
                  <.icon name="hero-pencil" class="size-4" />
                </button>
                <button
                  id={"delete-section-#{section.id}"}
                  phx-click="delete_section"
                  phx-value-id={section.id}
                  data-confirm="Delete this section and all its pages?"
                  class="rounded p-1 text-base-content/60 transition-colors hover:text-error"
                  title="Delete section"
                >
                  <.icon name="hero-trash" class="size-4" />
                </button>
              </div>
            </div>
            <ul class="mt-2 space-y-1">
              <li
                :for={page <- section.pages}
                id={"guide-page-row-#{page.id}"}
                class={[
                  "flex items-center justify-between rounded px-2 py-1 text-sm",
                  @page && @page.id == page.id && "bg-primary/15"
                ]}
              >
                <button
                  id={"edit-page-#{page.id}"}
                  phx-click="edit_page"
                  phx-value-id={page.id}
                  class="text-left transition-colors hover:text-primary"
                >
                  {page.title}
                </button>
                <button
                  id={"delete-page-#{page.id}"}
                  phx-click="delete_page"
                  phx-value-id={page.id}
                  data-confirm="Delete this page?"
                  class="text-base-content/50 transition-colors hover:text-error"
                  title="Delete page"
                >
                  <.icon name="hero-x-mark" class="size-4" />
                </button>
              </li>
            </ul>
            <button
              id={"new-page-#{section.id}"}
              phx-click="new_page"
              phx-value-section-id={section.id}
              class="mt-2 inline-flex items-center gap-1 text-xs font-semibold text-secondary transition-colors hover:text-primary"
            >
              <.icon name="hero-plus" class="size-3" /> Add page
            </button>
          </div>
        </section>

        <section id="guide-editor">
          <div
            :if={is_nil(@page_form)}
            id="guide-editor-empty"
            class="rounded-xl border border-dashed border-secondary/30 p-8 text-center text-sm text-base-content/60"
          >
            Pick a page to edit, or add one to a section. Pages are written in Markdown.
          </div>

          <div :if={@page_form} class="grid gap-6 2xl:grid-cols-2">
            <div class="rounded-xl border border-secondary/20 bg-base-200/80 p-4">
              <.form
                for={@page_form}
                id="page-form"
                phx-change="validate_page"
                phx-submit="save_page"
              >
                <.input
                  field={@page_form[:section_id]}
                  type="select"
                  label="Section"
                  options={Enum.map(@sections, &{&1.title, &1.id})}
                />
                <.input field={@page_form[:title]} type="text" label="Title" required />
                <.input field={@page_form[:position]} type="number" label="Position" min="0" />
                <.input
                  field={@page_form[:body]}
                  type="textarea"
                  label="Content (Markdown)"
                  rows="18"
                  phx-debounce="300"
                />
                <div class="flex gap-2">
                  <.button id="save-page" phx-disable-with="Saving...">Save page</.button>
                  <.button type="button" id="cancel-page" phx-click="cancel_page">Close</.button>
                </div>
              </.form>
            </div>
            <div class="rounded-xl border border-secondary/20 bg-base-200/50 p-4">
              <h2 class="text-xs font-bold uppercase tracking-[0.2em] text-secondary">Preview</h2>
              <.markdown id="page-preview" content={@preview} class="mt-3" />
            </div>
          </div>
        </section>
      </div>
    </Layouts.app>
    """
  end
end
