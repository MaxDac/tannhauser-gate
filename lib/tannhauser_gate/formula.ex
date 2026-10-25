defmodule TannhauserGate.Formula do
  use Gettext, backend: TannhauserGateWeb.Gettext

  @moduledoc """
  A small, safe arithmetic formula language used by GDR configuration
  (tracker maximums, XP costs).

  Supported syntax:

    * non-negative integer literals (`3`, `10`)
    * `+`, `-`, `*`, `/` (integer division, truncated) and unary minus
    * parentheses
    * `min(a, b, ...)` and `max(a, b, ...)`
    * identifiers (`[a-z][a-z0-9_]*`) resolved from a variables map, such as
      sheet item slugs (`stamina`, `resolve`) or named variables (`current`,
      `next`)

  Formulas are parsed by a hand-written recursive-descent parser into a plain
  AST; nothing is ever evaluated as Elixir code and identifiers are kept as
  strings (never converted to atoms).

      iex> TannhauserGate.Formula.evaluate("stamina + 3", %{"stamina" => 2})
      {:ok, 5}

      iex> TannhauserGate.Formula.evaluate("next * 5", %{"next" => 3})
      {:ok, 15}
  """

  import Ecto.Changeset, only: [get_change: 2, add_error: 3]

  @max_length 200
  @max_depth 32
  @functions ~w(min max)

  @type ast ::
          {:num, integer()}
          | {:var, String.t()}
          | {:neg, ast()}
          | {:op, :add | :sub | :mul | :div, ast(), ast()}
          | {:call, String.t(), [ast()]}

  @doc "Names reserved by the language (cannot be used as identifiers)."
  def reserved, do: @functions

  @doc "Parses a formula into an AST."
  @spec parse(String.t()) :: {:ok, ast()} | {:error, String.t()}
  def parse(formula) when is_binary(formula) do
    formula = String.trim(formula)

    cond do
      formula == "" ->
        {:error, dgettext("domain", "is empty")}

      String.length(formula) > @max_length ->
        {:error,
         dgettext("domain", "is too long (max %{max_length} characters)", max_length: @max_length)}

      true ->
        with {:ok, tokens} <- tokenize(formula, []),
             {:ok, ast, []} <- parse_expr(tokens, 0) do
          {:ok, ast}
        else
          {:ok, _ast, [token | _]} ->
            {:error, dgettext("domain", "unexpected %{token}", token: describe(token))}

          {:error, _} = error ->
            error
        end
    end
  end

  def parse(_), do: {:error, dgettext("domain", "is not a formula")}

  @doc "The identifiers a formula (or AST) references, deduplicated."
  def identifiers(formula) when is_binary(formula) do
    case parse(formula) do
      {:ok, ast} -> identifiers(ast)
      _ -> []
    end
  end

  def identifiers(ast), do: ast |> collect_vars([]) |> Enum.reverse() |> Enum.uniq()

  @doc """
  Checks a formula parses and only references the `allowed` identifiers.
  """
  @spec validate(String.t(), [String.t()]) :: :ok | {:error, String.t()}
  def validate(formula, allowed) do
    with {:ok, ast} <- parse(formula) do
      case identifiers(ast) -- allowed do
        [] ->
          :ok

        unknown ->
          {:error,
           dgettext("domain", "references unknown names: %{names}",
             names: Enum.join(unknown, ", ")
           )}
      end
    end
  end

  @doc """
  Evaluates a formula (string or AST) with the given variables map
  (string keys, integer values).
  """
  @spec evaluate(String.t() | ast(), %{optional(String.t()) => integer()}) ::
          {:ok, integer()} | {:error, String.t()}
  def evaluate(formula, vars) when is_binary(formula) do
    with {:ok, ast} <- parse(formula), do: evaluate(ast, vars)
  end

  def evaluate(ast, vars) when is_map(vars) do
    {:ok, eval(ast, vars)}
  catch
    {:formula_error, message} -> {:error, message}
  end

  @doc """
  Ecto validation: the formula in `field` (if changed) must parse and only
  reference `allowed` identifiers.
  """
  def validate_formula(changeset, field, allowed) do
    case get_change(changeset, field) do
      nil ->
        changeset

      formula ->
        case validate(formula, allowed) do
          :ok -> changeset
          {:error, message} -> add_error(changeset, field, message)
        end
    end
  end

  # -- Tokenizer -------------------------------------------------------------

  defp tokenize(<<>>, acc), do: {:ok, Enum.reverse(acc)}

  defp tokenize(<<c, rest::binary>>, acc) when c in [?\s, ?\t, ?\n, ?\r],
    do: tokenize(rest, acc)

  defp tokenize(<<c, _::binary>> = input, acc) when c in ?0..?9 do
    {digits, rest} = take_while(input, &(&1 in ?0..?9))

    if byte_size(digits) > 9 do
      {:error, dgettext("domain", "number %{digits} is too large", digits: digits)}
    else
      tokenize(rest, [{:num, String.to_integer(digits)} | acc])
    end
  end

  defp tokenize(<<c, _::binary>> = input, acc) when c in ?a..?z or c in ?A..?Z do
    {word, rest} = take_while(input, &(&1 in ?a..?z or &1 in ?A..?Z or &1 in ?0..?9 or &1 == ?_))
    tokenize(rest, [{:ident, String.downcase(word)} | acc])
  end

  defp tokenize(<<c, rest::binary>>, acc) when c in ~c"+-*/(),",
    do: tokenize(rest, [{:sym, <<c>>} | acc])

  defp tokenize(<<c::utf8, _::binary>>, _acc),
    do: {:error, dgettext("domain", "invalid character \"%{character}\"", character: <<c::utf8>>)}

  defp tokenize(_, _acc), do: {:error, dgettext("domain", "contains invalid characters")}

  defp take_while(input, fun), do: take_while(input, fun, "")

  defp take_while(<<c, rest::binary>>, fun, acc) do
    if fun.(c), do: take_while(rest, fun, acc <> <<c>>), else: {acc, <<c, rest::binary>>}
  end

  defp take_while(<<>>, _fun, acc), do: {acc, ""}

  # -- Parser ----------------------------------------------------------------
  # expr   := term (("+" | "-") term)*
  # term   := factor (("*" | "/") factor)*
  # factor := "-" factor | number | ident | ident "(" args ")" | "(" expr ")"

  defp parse_expr(_tokens, depth) when depth > @max_depth,
    do: {:error, dgettext("domain", "is nested too deeply")}

  defp parse_expr(tokens, depth) do
    with {:ok, left, rest} <- parse_term(tokens, depth), do: expr_loop(left, rest, depth)
  end

  defp expr_loop(left, [{:sym, op} | rest], depth) when op in ["+", "-"] do
    with {:ok, right, rest} <- parse_term(rest, depth) do
      expr_loop({:op, op_name(op), left, right}, rest, depth)
    end
  end

  defp expr_loop(left, rest, _depth), do: {:ok, left, rest}

  defp parse_term(tokens, depth) do
    with {:ok, left, rest} <- parse_factor(tokens, depth), do: term_loop(left, rest, depth)
  end

  defp term_loop(left, [{:sym, op} | rest], depth) when op in ["*", "/"] do
    with {:ok, right, rest} <- parse_factor(rest, depth) do
      term_loop({:op, op_name(op), left, right}, rest, depth)
    end
  end

  defp term_loop(left, rest, _depth), do: {:ok, left, rest}

  defp parse_factor(_tokens, depth) when depth > @max_depth,
    do: {:error, dgettext("domain", "is nested too deeply")}

  defp parse_factor([{:sym, "-"} | rest], depth) do
    with {:ok, inner, rest} <- parse_factor(rest, depth + 1), do: {:ok, {:neg, inner}, rest}
  end

  defp parse_factor([{:num, n} | rest], _depth), do: {:ok, {:num, n}, rest}

  defp parse_factor([{:ident, name}, {:sym, "("} | rest], depth) do
    if name in @functions do
      with {:ok, args, rest} <- parse_args(rest, depth + 1, []) do
        {:ok, {:call, name, args}, rest}
      end
    else
      {:error, dgettext("domain", "unknown function %{name}", name: name)}
    end
  end

  defp parse_factor([{:ident, name} | _rest], _depth) when name in @functions,
    do: {:error, dgettext("domain", "%{name} must be called like %{name}(a, b)", name: name)}

  defp parse_factor([{:ident, name} | rest], _depth), do: {:ok, {:var, name}, rest}

  defp parse_factor([{:sym, "("} | rest], depth) do
    case parse_expr(rest, depth + 1) do
      {:ok, inner, [{:sym, ")"} | rest]} -> {:ok, inner, rest}
      {:ok, _inner, _} -> {:error, dgettext("domain", "is missing a closing parenthesis")}
      error -> error
    end
  end

  defp parse_factor([], _depth), do: {:error, dgettext("domain", "ends unexpectedly")}

  defp parse_factor([token | _], _depth),
    do: {:error, dgettext("domain", "unexpected %{token}", token: describe(token))}

  defp parse_args(tokens, depth, acc) do
    case parse_expr(tokens, depth) do
      {:ok, arg, [{:sym, ","} | rest]} -> parse_args(rest, depth, [arg | acc])
      {:ok, arg, [{:sym, ")"} | rest]} -> {:ok, Enum.reverse([arg | acc]), rest}
      {:ok, _arg, _} -> {:error, dgettext("domain", "is missing a closing parenthesis")}
      error -> error
    end
  end

  defp op_name("+"), do: :add
  defp op_name("-"), do: :sub
  defp op_name("*"), do: :mul
  defp op_name("/"), do: :div

  defp describe({:sym, s}), do: "\"#{s}\""
  defp describe({:num, n}), do: dgettext("domain", "number %{number}", number: n)
  defp describe({:ident, name}), do: dgettext("domain", "name %{name}", name: name)

  # -- Evaluation ------------------------------------------------------------

  defp eval({:num, n}, _vars), do: n

  defp eval({:var, name}, vars) do
    case Map.fetch(vars, name) do
      {:ok, value} when is_integer(value) -> value
      _ -> throw({:formula_error, dgettext("domain", "unknown name %{name}", name: name)})
    end
  end

  defp eval({:neg, inner}, vars), do: -eval(inner, vars)
  defp eval({:op, :add, a, b}, vars), do: eval(a, vars) + eval(b, vars)
  defp eval({:op, :sub, a, b}, vars), do: eval(a, vars) - eval(b, vars)
  defp eval({:op, :mul, a, b}, vars), do: eval(a, vars) * eval(b, vars)

  defp eval({:op, :div, a, b}, vars) do
    case eval(b, vars) do
      0 -> throw({:formula_error, dgettext("domain", "division by zero")})
      divisor -> div(eval(a, vars), divisor)
    end
  end

  defp eval({:call, "min", args}, vars), do: args |> Enum.map(&eval(&1, vars)) |> Enum.min()
  defp eval({:call, "max", args}, vars), do: args |> Enum.map(&eval(&1, vars)) |> Enum.max()

  defp collect_vars({:var, name}, acc), do: [name | acc]
  defp collect_vars({:neg, inner}, acc), do: collect_vars(inner, acc)
  defp collect_vars({:op, _, a, b}, acc), do: collect_vars(b, collect_vars(a, acc))
  defp collect_vars({:call, _, args}, acc), do: Enum.reduce(args, acc, &collect_vars/2)
  defp collect_vars(_, acc), do: acc
end
