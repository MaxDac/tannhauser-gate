defmodule TannhauserGate.FormulaTest do
  use ExUnit.Case, async: true

  alias TannhauserGate.Formula

  describe "evaluate/2" do
    test "integers, operators, precedence and parentheses" do
      assert Formula.evaluate("1 + 2 * 3", %{}) == {:ok, 7}
      assert Formula.evaluate("(1 + 2) * 3", %{}) == {:ok, 9}
      assert Formula.evaluate("10 - 4 - 3", %{}) == {:ok, 3}
      assert Formula.evaluate("7 / 2", %{}) == {:ok, 3}
      assert Formula.evaluate("-3 + 5", %{}) == {:ok, 2}
      assert Formula.evaluate("  42 ", %{}) == {:ok, 42}
    end

    test "min, max and variables" do
      vars = %{"current" => 2, "next" => 3, "stamina" => 4}
      assert Formula.evaluate("next * 5", vars) == {:ok, 15}
      assert Formula.evaluate("max(current, 3) + min(stamina, 10)", vars) == {:ok, 7}
      assert Formula.evaluate("stamina + 3", vars) == {:ok, 7}
    end

    test "errors" do
      assert {:error, _} = Formula.evaluate("1 / 0", %{})
      assert {:error, _} = Formula.evaluate("unknown + 1", %{})
      assert {:error, _} = Formula.evaluate("1 +", %{})
      assert {:error, _} = Formula.evaluate("(1 + 2", %{})
      assert {:error, _} = Formula.evaluate("System.halt()", %{})
      assert {:error, _} = Formula.evaluate("1; 2", %{})
      assert {:error, _} = Formula.evaluate("", %{})
      assert {:error, _} = Formula.evaluate(String.duplicate("1+", 150) <> "1", %{})
    end

    test "never creates atoms from the input" do
      name = "never_seen_identifier_#{System.unique_integer([:positive])}"
      assert {:error, _} = Formula.evaluate(name, %{})
      assert_raise ArgumentError, fn -> String.to_existing_atom(name) end
    end
  end

  describe "validate/2" do
    test "accepts only the allowed identifiers" do
      assert :ok = Formula.validate("next * 3 + strength", ["next", "strength"])
      assert {:error, message} = Formula.validate("next * dexterity", ["next"])
      assert message =~ "dexterity"
      assert {:error, _} = Formula.validate("2 +* 3", [])
    end
  end
end
