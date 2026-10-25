defmodule TannhauserGate.Items.Listing do
  use Gettext, backend: TannhauserGateWeb.Gettext

  @moduledoc """
  An item sold by a shop: the price overrides the item's base price when set,
  the stock is unlimited when nil.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "shop_listings" do
    field :price, :integer
    field :stock, :integer
    field :position, :integer, default: 0

    belongs_to :shop, TannhauserGate.Items.Shop
    belongs_to :item, TannhauserGate.Items.Item

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(listing, attrs) do
    listing
    |> cast(attrs, [:item_id, :price, :stock, :position])
    |> validate_required([:item_id])
    |> validate_number(:price, greater_than_or_equal_to: 0, less_than_or_equal_to: 1_000_000_000)
    |> validate_number(:stock, greater_than_or_equal_to: 0, less_than_or_equal_to: 1_000_000)
    |> validate_number(:position, greater_than_or_equal_to: 0, less_than_or_equal_to: 1_000)
    |> unique_constraint(:item_id,
      name: :shop_listings_shop_id_item_id_index,
      message: dgettext_noop("errors", "is already sold by this shop")
    )
    |> check_constraint(:stock, name: :shop_listings_stock_non_negative)
    |> check_constraint(:price, name: :shop_listings_price_non_negative)
  end

  @doc "The unit price: the override, or the item's base price."
  def unit_price(%__MODULE__{price: nil, item: %{price: price}}), do: price
  def unit_price(%__MODULE__{price: price}), do: price
end
