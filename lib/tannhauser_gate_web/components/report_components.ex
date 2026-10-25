defmodule TannhauserGateWeb.ReportComponents do
  @moduledoc """
  Components of the reports and sanctions module: the small flag link shown
  next to reportable content, and the status and kind badges of the master
  queues.
  """
  use Phoenix.Component

  use Phoenix.VerifiedRoutes,
    endpoint: TannhauserGateWeb.Endpoint,
    router: TannhauserGateWeb.Router,
    statics: TannhauserGateWeb.static_paths()

  import TannhauserGateWeb.CoreComponents, only: [icon: 1]

  @doc """
  A small flag icon linking to the report form of a piece of content. Render
  it only when the `:reports` module is enabled and the content is not the
  user's own.
  """
  attr :id, :string, required: true
  attr :story, :map, required: true
  attr :type, :string, required: true
  attr :target_id, :integer, required: true
  attr :return_to, :string, default: nil
  attr :label, :string, default: nil
  attr :class, :any, default: nil

  def report_link(assigns) do
    ~H"""
    <.link
      id={@id}
      navigate={
        ~p"/g/#{@story}/report?#{[type: @type, id: @target_id] ++ if(@return_to, do: [return_to: @return_to], else: [])}"
      }
      class={[
        "inline-flex items-center gap-1 text-xs text-base-content/40 transition-colors hover:text-warning",
        @class
      ]}
      title="Report to the masters"
      aria-label="Report to the masters"
    >
      <.icon name="hero-flag" class="size-3" />
      <span :if={@label}>{@label}</span>
    </.link>
    """
  end

  @doc "A badge for a report status."
  attr :id, :string, default: nil
  attr :status, :string, required: true

  def report_status_badge(assigns) do
    ~H"""
    <span
      id={@id}
      class={[
        "badge badge-sm badge-soft",
        case @status do
          "open" -> "badge-warning"
          "resolved" -> "badge-success"
          _ -> "badge-ghost"
        end
      ]}
    >
      {TannhauserGate.Reports.status_label(@status)}
    </span>
    """
  end

  @doc "A badge for a sanction kind."
  attr :id, :string, default: nil
  attr :kind, :string, required: true

  def sanction_kind_badge(assigns) do
    ~H"""
    <span
      id={@id}
      class={[
        "badge badge-sm badge-soft uppercase tracking-wider",
        case @kind do
          "ban" -> "badge-error"
          "mute" -> "badge-warning"
          _ -> "badge-info"
        end
      ]}
    >
      {@kind}
    </span>
    """
  end
end
