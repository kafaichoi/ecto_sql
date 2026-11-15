defmodule Ecto.Integration.PrepareTest do
  use Ecto.Integration.Case, async: true

  alias Ecto.Integration.TestRepo
  alias Ecto.Integration.Post

  defmodule Item do
    use Ecto.Schema

    schema "items" do
      field :value, :integer
    end
  end

  test "prepare option" do
    one = TestRepo.insert!(%Post{title: "one"})
    two = TestRepo.insert!(%Post{title: "two"})

    # Uncached
    assert TestRepo.all(Post, prepare: :unnamed) == [one, two]
    assert TestRepo.all(Post, prepare: :named) == [one, two]

    # Cached
    assert TestRepo.all(Post, prepare: :unnamed) == [one, two]
    assert TestRepo.all(Post, prepare: :named) == [one, two]
  end

  test "inserts with long source names write to the intended table" do
    prefix = "prepare_test_" <> String.duplicate("x", 38)
    first = prefix <> "_a"
    second = prefix <> "_b"
    create_table(first)
    create_table(second)

    # The old names only differ after byte 63. Matching parameter types would
    # let a cached insert silently execute the other table's statement.
    insert_item!(first, 1)
    insert_item!(second, 2)
    insert_item!(first, 3)
    insert_item!(second, 4)

    assert values(first) == [[1], [3]]
    assert values(second) == [[2], [4]]

    assert [[name]] = statement_names(first)
    assert name =~ ~r/^ecto_insert_prepare_test_x+[0-9]+_0$/
    assert byte_size(name) == 63
  end

  test "bulk inserts with multibyte source names write to the intended table" do
    prefix = String.duplicate("é", 24) <> "xé"
    first = prefix <> "_a"
    second = prefix <> "_b"
    create_table(first)
    create_table(second)

    assert {1, nil} = TestRepo.insert_all(first, [%{value: 1}])
    assert {1, nil} = TestRepo.insert_all(second, [%{value: 2}])
    assert {1, nil} = TestRepo.insert_all(first, [%{value: 3}])
    assert {1, nil} = TestRepo.insert_all(second, [%{value: 4}])

    assert values(first) == [[1], [3]]
    assert values(second) == [[2], [4]]

    assert [[name]] = statement_names(first)
    assert name =~ ~r/^ecto_insert_all_x_a[0-9]+$/
    assert byte_size(name) <= 63
  end

  test "long sources without ASCII bytes use only a hash" do
    source = String.duplicate("é", 30)
    create_table(source)
    insert_item!(source, 1)

    assert [[name]] = statement_names(source)
    assert name =~ ~r/^ecto_insert_[0-9]+_0$/
    assert byte_size(name) <= 63
    assert values(source) == [[1]]
  end

  test "preserves names at the limit and explicit cache options" do
    source = String.duplicate("s", 49)
    name = "ecto_insert_#{source}_0"
    assert byte_size(name) == 63
    create_table(source)

    insert_item!(source, 1, cache_statement: false)
    assert statement_names(source) == []

    insert_item!(source, 2)
    assert statement_names(source) == [[name]]

    insert_item!(source, 3, cache_statement: "custom_statement")
    assert statement_names(source) == [["custom_statement"], [name]]
    assert values(source) == [[1], [2], [3]]
  end

  defp create_table(source) do
    TestRepo.query!(~s|CREATE TEMP TABLE "#{source}" (id bigserial PRIMARY KEY, value integer)|)
  end

  defp insert_item!(source, value, opts \\ []) do
    %Item{value: value}
    |> Ecto.put_meta(source: source)
    |> TestRepo.insert!(opts)
  end

  defp values(source) do
    TestRepo.query!(~s|SELECT value FROM "#{source}" ORDER BY value|).rows
  end

  defp statement_names(source) do
    TestRepo.query!(
      "SELECT name FROM pg_prepared_statements WHERE statement LIKE $1 ORDER BY name",
      [~s|INSERT INTO "#{source}"%|]
    ).rows
  end
end
