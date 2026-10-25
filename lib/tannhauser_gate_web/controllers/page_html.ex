defmodule TannhauserGateWeb.PageHTML do
  @moduledoc """
  Static pages: the terms and disclaimer accepted at registration.
  """
  use TannhauserGateWeb, :html

  def terms(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <article id="terms" class="mx-auto max-w-2xl space-y-4 text-sm leading-relaxed text-fog-200">
        <.header>
          {dgettext("player", "Terms and disclaimer")}
          <:subtitle>{dgettext("player", "Read them before creating an account.")}</:subtitle>
        </.header>

        <section id="terms-fiction">
          <h2 class="font-bold uppercase tracking-wider text-mint">
            {dgettext("player", "Fiction")}
          </h2>

          <p>
            {dgettext(
              "player",
              "The GDRs hosted here are play-by-chat role playing games. Their worlds, characters, places and events are fictional: any resemblance to real people or facts is a coincidence. Stories may deal with mature themes such as violence or crime, depicted for narrative purposes only."
            )}
          </p>
        </section>

        <section id="terms-conduct">
          <h2 class="font-bold uppercase tracking-wider text-mint">
            {dgettext("player", "Conduct")}
          </h2>

          <p>
            {dgettext(
              "player",
              "Be respectful of the other players, in and out of character. Harassment, hate speech and illegal content are not allowed. The masters and the GDR admins may moderate the chats, the forum and the characters, and the platform admins may suspend accounts that break these rules."
            )}
          </p>
        </section>

        <section id="terms-data">
          <h2 class="font-bold uppercase tracking-wider text-mint">
            {dgettext("player", "Your data")}
          </h2>

          <p>
            {dgettext(
              "player",
              "We store your username, email and the content you write (characters, chat messages, forum posts and letters) to run the games. Chat messages and letters can be read by the masters of the GDR for moderation."
            )}
          </p>
        </section>

        <section id="terms-disclaimer">
          <h2 class="font-bold uppercase tracking-wider text-mint">
            {dgettext("player", "Disclaimer")}
          </h2>

          <p>
            {dgettext(
              "player",
              "The service is provided as is, without warranties. Contents written by the players are their own responsibility."
            )}
          </p>
        </section>

        <p :if={is_nil(@current_user)}>
          <.link navigate={~p"/users/register"} class="font-semibold text-mint hover:underline">
            {dgettext("player", "Back to the registration")}
          </.link>
        </p>
      </article>
    </Layouts.app>
    """
  end
end
