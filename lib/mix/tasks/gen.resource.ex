defmodule Mix.Tasks.PhoenixConfig.Gen.Resource do
  use Mix.Task

  alias Mix.PhoenixConfigHelpers
  alias PhoenixConfig.{EctoSchemaReflector, EctoContextGenerator}

  @shortdoc "Creates a resource file that will be used to configure absinthe routes and can create schemas"
  @moduledoc """
  You can use this to create all resources needed for a GraphQL API

  ### Existing Schema
  If you have an existing schema, you can use the `--from-ecto-schema` flag with the `--context` flag
  to generate a config file for that specific flle

  #### Example

  ```bash
  > mix phoenix_config.gen.resource --context MyApp.SomeContext --from-ecto-schema MyApp.SomeContext.Schema
  ```

  ### New Schema
  If you're creating a new schema, you can pass in the same arguments you would to `mix phx.gen.schema`

  #### Example

  ```bash
  > mix phoenix_config.gen.resource Accounts.User email:string name:string birthday:date
  ```

  ### Options
  - `dirname` - The directory to generate the config files in
  - `file_name` - The file name for the config
  - `only` - Parts to generate (create, all, find, update, delete)
  - `except` - Parts of the CRUD resource to exclude
  - `context` - Context module if supplying `--from-ecto-schema`
  - `from-ecto-schema` - Specify a specific module instead of generating a new schema
  """

  def run(args) do
    PhoenixConfigHelpers.ensure_not_in_umbrella!("phoenix_config.gen.resource")

    {opts, extra_args, _} = OptionParser.parse(args,
      switches: [
        dirname: :string,
        file_name: :string,
        only: :keep,
        except: :keep,
        context: :string,
        from_ecto_schema: :string
      ]
    )

    PhoenixConfigHelpers.ensure_init_run!(opts[:dirname])

    cond do
      !opts[:from_ecto_schema] and Enum.empty?(extra_args) ->
        Mix.raise("Must provide a from_ecto_schema or create a schema for mix phoenix_config.gen.resource using the --from-ecto-schema flag")

      !opts[:context] and Enum.empty?(extra_args) ->
        Mix.raise("Must provide a context or create a schema for mix phoenix_config.gen.resource using the --context flag")

      opts[:from_ecto_schema] && opts[:context] ->
        create_and_write_resource_from_schema(opts)

      extra_args ->
        {context_module, ecto_schema} = create_schema_from_args(extra_args)

        opts
          |> Keyword.merge(from_ecto_schema: ecto_schema, context: context_module)
          |> create_and_write_resource_from_schema
    end
  end

  defp create_and_write_resource_from_schema(opts) do
    from_ecto_schema = Module.safe_concat([opts[:from_ecto_schema]])
    context = Module.safe_concat([opts[:context]])

    contents = create_config_contents(context, from_ecto_schema, opts[:only], opts[:except])
    file_name = opts[:file_name] || EctoSchemaReflector.ecto_module_resource_name(from_ecto_schema)

    PhoenixConfigHelpers.write_phoenix_config_file(opts[:dirname], file_name, contents)
  end

  defp create_config_contents(context_module, schema_name, nil, nil) do
    """
    import PhoenixConfig, only: [crud_from_schema: 2]

    [
      crud_from_schema(#{inspect(context_module)}, #{inspect(schema_name)})
    ]
    """
  end

  defp create_config_contents(context_module, schema_name, only, except) do
    """
    import PhoenixConfig, only: [crud_from_schema: 4]

    [
      crud_from_schema(#{inspect(context_module)}, #{inspect(schema_name)}, #{inspect(only)}, #{inspect(except)})
    ]
    """
  end

  defp create_schema_from_args(extra_args) do
    with :ok <- Mix.Tasks.Phx.Gen.Schema.run(extra_args) do
      context_app = Mix.Phoenix.context_app() |> to_string |> Macro.camelize

      schema_module = hd(extra_args)
      context_module = context_module_from_schema_module(schema_module)
      ecto_schema = Module.safe_concat(context_app, schema_module)
      context_module = ensure_context_module_created(Mix.Phoenix.context_app(), context_module, ecto_schema)

      {inspect(context_module), inspect(ecto_schema)}
    end
  end

  defp ensure_context_module_created(context_app, context_module, ecto_schema) do
    context_app_module = context_app |> to_string |> Macro.camelize

    Module.safe_concat(context_app_module, context_module)

    rescue
      ArgumentError ->
        context_app_module = context_app |> to_string |> Macro.camelize

        Mix.shell().info("No context found for schema at #{context_app_module}.#{context_module}, creating...")

        context_module_path = Mix.Phoenix.context_lib_path(context_app, "#{Macro.underscore(context_module)}.ex")

        if Mix.Generator.create_file(context_module_path, EctoContextGenerator.create_context_module_for_schemas(context_app_module, context_module, [ecto_schema])) do
          Code.compile_file(context_module_path)

          Module.safe_concat(context_app_module, context_module)
        end
  end

  defp context_module_from_schema_module(schema_module) do
    case schema_module |> to_string |> String.split(".") do
      [item] -> item
      schema_parts -> schema_parts |> Enum.drop(-1) |> Enum.join(".")
    end
  end
end

