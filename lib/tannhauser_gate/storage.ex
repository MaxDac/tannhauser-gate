defmodule TannhauserGate.Storage do
  @moduledoc """
  Minimal local-disk storage for uploaded images (character avatars).

  Files are written to `uploads_dir/0` and served by `Plug.Static` under
  `/uploads`. Configure a different directory with:

      config :tannhauser_gate, :uploads_dir, "/var/lib/tannhauser_gate/uploads"
  """

  @allowed_extensions ~w(.jpg .jpeg .png .gif .webp)

  def allowed_extensions, do: @allowed_extensions

  def uploads_dir do
    Application.get_env(:tannhauser_gate, :uploads_dir) ||
      Application.app_dir(:tannhauser_gate, "priv/static/uploads")
  end

  @doc """
  Copies the file at `source_path` into the uploads directory under a random
  name and returns its public path (e.g. `"/uploads/3f2c...png"`).
  """
  def store_upload!(source_path, client_name) do
    ext = client_name |> Path.extname() |> String.downcase()
    ext = if ext in @allowed_extensions, do: ext, else: ".bin"
    filename = Ecto.UUID.generate() <> ext
    dir = uploads_dir()

    File.mkdir_p!(dir)
    File.cp!(source_path, Path.join(dir, filename))

    "/uploads/" <> filename
  end

  @doc """
  Sniffs the image type of a file from its first bytes: `:png`, `:jpeg`,
  `:webp`, `:gif` or `nil` for anything else (SVG included).
  """
  def image_type(path) do
    case File.open(path, [:read, :binary], &IO.binread(&1, 12)) do
      {:ok, <<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A, _::binary>>} -> :png
      {:ok, <<0xFF, 0xD8, 0xFF, _::binary>>} -> :jpeg
      {:ok, <<"RIFF", _size::binary-size(4), "WEBP">>} -> :webp
      {:ok, <<"GIF8", _::binary>>} -> :gif
      _ -> nil
    end
  end
end
