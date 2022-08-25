Mix.install([
  {:xlsx_reader, "~> 0.5.0"},
  {:jason, "~> 1.3"}
])

defmodule TmfReferenceModel.Loader do
  @moduledoc """
  Loads the TMF Reference model workbook and extracts
  the first sheet into a list of lists.
  """
  @custom_formats [
    {"##.##", :string},
    {"00.00", :string},
    {"0.0", :string},
    {"#.#", :string}
  ]

  def load(input_file_path) do
    {:ok, package} = XlsxReader.open(input_file_path, supported_custom_formats: @custom_formats)

    [sheet | _] = XlsxReader.sheet_names(package)

    XlsxReader.sheet(package, sheet, empty_rows: false, number_type: String)
  end
end

defmodule TmfReferenceModel.Transformer do
  @moduledoc """
  For the list of rows in a Worksheet, transform it
  into an elixir map.
  """

  @doc """
  transform/1 takes a list of rows from the TMF Reference model spreadsheet
  and converts it into an Elixir map.
  """
  def transform(rows) when is_list(rows) do
    rows
    |> parse_header_rows()
    |> transform_artifacts()
  end

  def transform({:ok, rows}), do: transform(rows)
  def transform(any), do: IO.inspect(any, label: "Error loading rows:")

  defp parse_header_rows(rows) do
    [title_row, headers_a, headers_b | rows] = rows

    %{
      metadata: title_row |> parse_metadata(),
      headers: parse_headers(headers_a, headers_b),
      rows: rows
    }
  end

  defp parse_metadata([title | title_row]) do
    ref_model_version =
      title_row
      |> Enum.find(&String.contains?(&1, "Version"))
      |> String.replace("Version", "")
      |> String.trim()

    ref_model_date =
      title_row
      |> Enum.find(&is_struct(&1, Date))
      |> to_string()

    title = title |> String.trim()

    %{
      :_generation_timestamp => DateTime.utc_now() |> DateTime.to_string(),
      title: title,
      version: ref_model_version,
      version_date: ref_model_date
    }
  end

  defp parse_headers(headers_a, headers_b) do
    # There are 2 header rows, we need to combine them to handle
    # sub sections and merged cells

    {_, headers} =
      Enum.zip_reduce(
        headers_a,
        headers_b,
        {"", []},
        fn a, b, {section, acc} ->
          {s, h} = combine_headers(a, b, section)

          # add header to accumulator list
          {s, [acc | [h |> String.replace("\r\n", " ") |> String.trim()]]}
        end
      )

    headers
    |> List.flatten()
  end

  def combine_headers(a, b, section)
  def combine_headers(a, "", _), do: {"", a}
  def combine_headers("", b, ""), do: {"", b}
  def combine_headers("", b, section), do: {"", concat_section_header(section, b)}
  def combine_headers(a, b, ""), do: {a, concat_section_header(a, b)}

  defp concat_section_header(section, header), do: Enum.join([section, header], " : ")

  defp transform_artifacts(%{metadata: metadata, headers: headers, rows: rows}) do
    artifacts =
      rows
      |> Enum.reject(fn [zone | _] -> zone == "" end)
      |> Enum.map(fn r ->
        # Combine the List of headers with the list of data from this row
        {_, artifact} =
          Enum.zip(headers, r)
          # Now convert the list of tuples into a map
         |> Enum.map_reduce(%{}, fn {k, v}, acc ->
            # if the value has `\r\n` in it, split into a list of strings
            value =
              v
              |> special_conversion_hack()
              |> split_string_with_multiple_lines()

            # Search for Section headers (from the headers) to create sub maps
            k
            |> has_section_marker?()
            |> case do
              true ->
                # Need to split key into section/header
                {true, add_section_to_artifact(acc, k, value)}
              false ->
                {true, acc |> Map.put(k, value)}
            end
          end)

        artifact
      end)

    %{metadata: metadata, artifacts: artifacts}
  end

  defp has_section_marker?(str), do: String.contains?(str, " : ")

  defp split_string_with_multiple_lines(str) when is_binary(str) do
    str
    |> String.split("\r\n")
    |> case do
      [any] -> any
      any -> any
    end
  end

  defp split_string_with_multiple_lines(other), do: other

  # Handle unexpected formatting in a given XLSX version of the reference model
  defp special_conversion_hack("2.2000000000000002"), do: "2.2"
  defp special_conversion_hack("2.0099999999999998"), do: "2.01"
  defp special_conversion_hack("10.050000000000001"), do: "10.05"
  defp special_conversion_hack(any), do: any

  defp add_section_to_artifact(artifact, key, value) do
    # split key into section/header
    [section, header] = String.split(key, " : ", trim: true, parts: 2)

    {_, new_artifact} =
      artifact
      |> Map.get_and_update(section, fn
        current_value when is_nil(current_value) ->
          {current_value, Map.new([{header, value}])}

        current_value ->
          {current_value, current_value |> Map.put(header, value)}
      end)

    new_artifact
  end
end

defmodule TmfReferenceModel.Encoder.Json do
  @moduledoc """
  For the output of the Transfomer module, convert the map
  into a JSON representation.
  """

  @doc """
  Given an Elixir Map, with `:metadata` and `:artifacts` keys,
  convert it into it's JSON representation.
  """
  def encode(%{metadata: metadata, artifacts: artifacts}) do
    %{
      :_metadata => metadata,
      artifacts: %{
        :_count => artifacts |> Enum.count(),
        items: artifacts
      }
    }
    |> Jason.encode!(pretty: true)
  end

  def encode(_), do: raise ArgumentError, "Must supply a map with metadata and artifacts keys"
end

defmodule TmfReferenceModel.Main do
  @moduledoc """
  Main entry point to the script
  """

  alias TmfReferenceModel.Loader
  alias TmfReferenceModel.Transformer
  alias TmfReferenceModel.Encoder.Json

  def main() do
    input_file = "Version-3.2.1-TMF-Reference-Model-v01-Mar-2021.xlsx"
    output_file = input_file |> String.replace("xlsx", "json")

    input_file
    |> Loader.load()
    |> Transformer.transform()
    |> Json.encode()
    |> then(&File.write(output_file, &1))

    IO.inspect(output_file, label: "Output written to")
  end
end

TmfReferenceModel.Main.main()
