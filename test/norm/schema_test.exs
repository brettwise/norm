defmodule Norm.SchemaTest do
  use ExUnit.Case, async: true
  import Norm
  import ExUnitProperties, except: [gen: 1]

  defmodule User do
    import Norm

    defstruct ~w|name email age|a

    def s,
      do:
        schema(%__MODULE__{
          name: spec(is_binary()),
          email: spec(is_binary()),
          age: spec(is_integer() and (&(&1 >= 0)))
        })

    def chris do
      %__MODULE__{name: "chris", email: "c@keathley.io", age: 31}
    end
  end

  defmodule OtherUser do
    defstruct ~w|name email age|a
  end

  test "creates a re-usable schema" do
    s = schema(%{name: spec(is_binary())})
    assert %{name: "Chris"} == conform!(%{name: "Chris"}, s)
    assert {:error, _errors} = conform(%{foo: "bar"}, s)
    assert {:error, _errors} = conform(%{name: 123}, s)

    user = schema(%{user: schema(%{name: spec(is_binary())})})
    assert %{user: %{name: "Chris"}} == conform!(%{user: %{name: "Chris"}}, user)
  end

  test "requires all of the keys specified in the schema" do
    s =
      schema(%{
        name: spec(is_binary()),
        age: spec(is_integer())
      })

    assert %{name: "chris", age: 31} == conform!(%{name: "chris", age: 31}, s)
    assert {:error, errors} = conform(%{name: "chris"}, s)
    assert errors == [%{spec: ":required", input: %{name: "chris"}, path: [:age]}]

    user = schema(%{user: s})
    assert {:error, errors} = conform(%{user: %{age: 31}}, user)
    assert errors == [%{spec: ":required", input: %{age: 31}, path: [:user, :name]}]
  end

  test "works with boolean values" do
    s = schema(%{bool: spec(is_boolean())})

    assert %{bool: true} == conform!(%{bool: true}, s)
    assert %{bool: false} == conform!(%{bool: false}, s)
  end

  test "allows keys to have nil values" do
    s = schema(%{foo: spec(is_nil())})

    assert %{foo: nil} == conform!(%{foo: nil}, s)
    assert {:error, errors} = conform(%{foo: 123}, s)
    assert errors == [%{spec: "is_nil()", input: 123, path: [:foo]}]
  end

  describe "generation" do
    test "works with maps" do
      s =
        schema(%{
          name: spec(is_binary()),
          age: spec(is_integer())
        })

      maps =
        s
        |> gen()
        |> Enum.take(10)

      for map <- maps do
        assert is_map(map)
        assert match?(%{name: _, age: _}, map)
        assert is_binary(map.name)
        assert is_integer(map.age)
      end
    end

    test "returns errors if it contains unknown generators" do
      s =
        schema(%{
          age: spec(&(&1 > 0))
        })

      assert_raise Norm.GeneratorError, "Unable to create a generator for: &(&1 > 0)", fn ->
        gen(s)
      end
    end
  end

  test "schemas can be composed with other specs" do
    user_or_other = alt(user: User.s(), other: schema(%OtherUser{}))
    user = User.chris()
    other = %OtherUser{}

    assert {:user, user} == conform!(user, user_or_other)
    assert {:other, other} == conform!(other, user_or_other)
    assert {:error, errors} = conform(%{}, user_or_other)

    assert errors == [
      %{spec: "Norm.SchemaTest.User", input: %{}, path: [:user]},
      %{spec: "Norm.SchemaTest.OtherUser", input: %{}, path: [:other]}
    ]
  end

  test "can have nested alts" do
    s = schema(%{a: alt(bool: spec(is_boolean()), int: spec(is_integer()))})

    assert %{a: {:bool, true}} == conform!(%{a: true}, s)
    assert %{a: {:bool, false}} == conform!(%{a: false}, s)
    assert %{a: {:int, 123}} == conform!(%{a: 123}, s)
    assert {:error, errors} = conform(%{a: "test"}, s)

    assert errors == [
      %{spec: "is_boolean()", input: "test", path: [:a, :bool]},
      %{spec: "is_integer()", input: "test", path: [:a, :int]}
    ]
  end

  test "only returns specced keys" do
    user_schema =
      schema(%{
        name: spec(is_binary())
      })

    assert {:ok, %{name: "chris"}} == conform(%{name: "chris", age: 31}, user_schema)
  end

  test "works with string keys and atom keys" do
    user =
      schema(%{
        "name" => spec(is_binary()),
        age: spec(is_integer())
      })

    input = %{
      "name" => "chris",
      age: 31
    }

    assert input == conform!(input, user)
    assert {:error, errors} = conform(%{"name" => 31, age: "chris"}, user)

    assert errors == [
      %{spec: "is_integer()", input: "chris", path: [:age]},
      %{spec: "is_binary()", input: 31, path: ["name"]}
    ]
  end

  describe "schema/1 with struct" do
    test "fails non-structs when the schema is a struct" do
      input = Map.from_struct(User.chris())

      assert {:error, errors} = conform(input, schema(%User{}))

      assert errors == [
        %{spec: "Norm.SchemaTest.User", input: %{age: 31, email: "c@keathley.io", name: "chris"}, path: []}
             ]
    end

    test "fails if the wrong struct is passed" do
      input = User.chris()

      assert {:error, errors} = conform(input, schema(%OtherUser{}))

      assert errors == [
        %{spec: "Norm.SchemaTest.OtherUser", input: %Norm.SchemaTest.User{age: 31, email: "c@keathley.io", name: "chris"}, path: []}
             ]
    end

    test "can create a schema from a struct" do
      s = schema(%User{})

      assert User.chris() == conform!(User.chris(), s)
    end

    test "can specify specs for keys" do
      input = User.chris()

      assert input == conform!(input, User.s())
      assert {:error, errors} = conform(%User{name: :foo, age: "31", email: 42}, User.s())

      assert errors == [
        %{spec: "is_integer()", input: "31", path: [:age]},
        %{spec: "is_binary()", input: 42, path: [:email]},
        %{spec: "is_binary()", input: :foo, path: [:name]}
      ]
    end

    test "only checks the keys that have specs" do
      input = User.chris()
      spec = schema(%User{name: spec(is_binary())})

      assert input == conform!(input, spec)
      assert {:error, errors} = conform(%User{name: 23}, spec)
      assert errors == [%{spec: "is_binary()", input: 23, path: [:name]}]
    end

    property "can generate proper structs" do
      check all(user <- gen(User.s())) do
        assert match?(%User{}, user)
        assert is_integer(user.age) and user.age >= 0
        assert is_binary(user.name)
        assert is_binary(user.email)
      end
    end

    property "can generate structs with a subset of keys specified" do
      check all(user <- gen(schema(%User{age: spec(is_integer() and (&(&1 > 0)))}))) do
        assert match?(%User{}, user)
        assert is_integer(user.age) and user.age >= 0
        assert is_nil(user.name)
        assert is_nil(user.email)
      end
    end
  end
end
